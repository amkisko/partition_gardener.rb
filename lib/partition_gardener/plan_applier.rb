module PartitionGardener
  class PlanApplier
    include Naming

    def initialize(config, executor: nil, job_class_name: "PartitionGardener")
      @config = config
      @executor = executor || Executor.for_config(config)
      @job_class_name = job_class_name
    end

    def apply!(plan)
      DefaultPartition.ensure!(@config, executor: @executor)
      attached = attached_tail_segments
      return unless plan.changed?(attached)

      table_name = @config[:table_name]
      staging_name = rebalance_staging_partition_name(table_name)
      plan_signature = PlanDiff.plan_signature(plan.segments)
      PartitionGardener.configuration.current_run_metrics&.plan_signature = plan_signature
      record = run_record_enabled? ? RunRecord.load(table_name) : nil

      guard_against_orphaned_staging!(staging_name, record, plan_signature)
      operations = PlanDiff.operations(attached, plan.segments)

      if resumable_run?(record, plan_signature, staging_name)
        notify_resume(record)
        apply_resuming!(plan, operations, staging_name, record)
      elsif incremental_rebalance?
        apply_incremental!(plan, operations, staging_name, plan_signature)
      else
        apply_full!(plan, staging_name, plan_signature)
      end

      analyze_parent_table!(table_name)
      notify_rebalance_complete(table_name, plan)
      RunRecord.clear(table_name) if run_record_enabled?
    end

    private

    def strategy
      Strategy.for(@config)
    end

    def conflict_key
      @config[:conflict_key] || begin
        [@config[:partition_key_column].split("::").first.strip, "id"].uniq
      end
    end

    def cursor_columns
      strategy.cursor_columns
    end

    def connection
      Connection.connection
    end

    def attached_tail_segments
      Planner.new(@config).attached_tail_segments
    end

    def managed_tail_partition_names
      strategy.managed_tail_partition_names
    end

    def incremental_rebalance?
      @config.fetch(:incremental_rebalance, PartitionGardener.configuration.incremental_rebalance)
    end

    def run_record_enabled?
      @config.fetch(:run_record_enabled, PartitionGardener.configuration.run_record_enabled)
    end

    def resumable_run?(record, plan_signature, staging_name)
      return false unless run_record_enabled? && record&.incomplete?
      return false unless record.plan_signature == plan_signature
      return false unless Connection.partition_exists?(staging_name)

      true
    end

    def guard_against_orphaned_staging!(staging_name, record, plan_signature)
      return unless Connection.partition_exists?(staging_name)
      return if resumable_run?(record, plan_signature, staging_name)

      row_count = Connection.count_rows_in_partition_table(staging_name)
      return if row_count.zero?

      raise OrphanedRebalanceStaging,
        "#{staging_name} holds #{row_count} row(s) from an interrupted rebalance; " \
        "restore a matching run record or move rows manually before maintenance"
    end

    def apply_full!(plan, staging_name, plan_signature)
      record = start_run_record(plan_signature) if run_record_enabled?

      prepare_staging!(staging_name)
      record&.advance!("detach")

      detach_managed_tail_partitions!(staging_name)
      drain_default_tail_rows_into_staging!(staging_name)
      record&.advance!("detach", staging_row_count: staging_row_count(staging_name))

      create_target_segments!(plan)
      record&.advance!("segments")

      move_staging_rows!(staging_name)
      record&.advance!("rows", staging_row_count: 0)

      @executor.drop_table(staging_name)
      record&.advance!("cleanup")
    end

    def apply_incremental!(plan, operations, staging_name, plan_signature)
      changed_operations = operations.reject { |operation| operation.action == :keep }
      return if changed_operations.empty?

      record = start_run_record(plan_signature) if run_record_enabled?
      keep_names = operations.select { |operation| operation.action == :keep }.map { |operation| operation.segment.name }

      prepare_staging!(staging_name)
      record&.advance!("detach")

      detach_managed_tail_partitions!(staging_name, skip_names: keep_names)
      drain_default_tail_rows_into_staging!(staging_name)
      record&.advance!("detach", staging_row_count: staging_row_count(staging_name))

      segments_to_create = changed_operations.filter_map(&:segment).uniq(&:name)
      create_segments!(segments_to_create)
      record&.advance!("segments")

      move_staging_rows!(staging_name)
      record&.advance!("rows", staging_row_count: 0)

      drop_removed_partitions!(operations)
      @executor.drop_table(staging_name)
      record&.advance!("cleanup")
    end

    def apply_resuming!(plan, operations, staging_name, record)
      unless record.phase_at_least?("detach")
        prepare_staging!(staging_name)
        detach_managed_tail_partitions!(staging_name, skip_names: keep_names_from(operations))
        drain_default_tail_rows_into_staging!(staging_name)
        record = record.advance!("detach", staging_row_count: staging_row_count(staging_name))
      end

      unless record.phase_at_least?("segments")
        create_target_segments!(plan)
        record = record.advance!("segments")
      end

      unless record.phase_at_least?("rows")
        move_staging_rows!(staging_name)
        record = record.advance!("rows", staging_row_count: 0)
      end

      drop_removed_partitions!(operations) if incremental_rebalance?

      unless record.phase_at_least?("cleanup")
        @executor.drop_table(staging_name) if Connection.partition_exists?(staging_name)
        record.advance!("cleanup")
      end
    end

    def keep_names_from(operations)
      operations.select { |operation| operation.action == :keep }.map { |operation| operation.segment.name }
    end

    def prepare_staging!(staging_name)
      @executor.drop_table(staging_name)
      @executor.ensure_detached_partition_table!(@config[:table_name], staging_name, conflict_key: conflict_key)
    end

    def create_target_segments!(plan)
      create_segments!(plan.segments)
    end

    def create_segments!(segments)
      return if MaintenanceBackend.hybrid?(@config)

      table_name = @config[:table_name]

      segments.each do |segment|
        next if Connection.partition_attached?(table_name, segment.name)

        @executor.create_partition(
          table_name,
          segment.name,
          segment.for_values_clause(strategy)
        )
      end
    end

    def move_staging_rows!(staging_name)
      table_name = @config[:table_name]
      return unless Connection.partition_exists?(staging_name)
      return if Connection.count_rows_in_partition_table(staging_name).zero?

      @executor.move_all_rows_to_parent!(table_name, staging_name, conflict_key, cursor_columns: cursor_columns)
    end

    def drop_removed_partitions!(operations)
      operations.select { |operation| operation.action == :drop }.each do |operation|
        partition_name = operation.attached_segment.name
        next if Connection.partition_attached?(@config[:table_name], partition_name)

        @executor.drop_table(partition_name) if Connection.partition_exists?(partition_name)
      end
    end

    def detach_managed_tail_partitions!(staging_name, skip_names: [])
      table_name = @config[:table_name]

      managed_tail_partition_names.each do |partition_name|
        next if skip_names.include?(partition_name)
        next unless Connection.partition_attached?(table_name, partition_name)

        @executor.detach_partition(table_name, partition_name)
        @executor.move_all_rows_between_partitions!(partition_name, staging_name, conflict_key, cursor_columns: cursor_columns)
        @executor.drop_table(partition_name)
      end
    end

    def drain_default_tail_rows_into_staging!(staging_name)
      default_name = default_partition_name(@config[:table_name])
      return unless Connection.partition_exists?(default_name)

      where_condition = strategy.rebalance_default_drain_where_condition
      return if where_condition == "FALSE"
      return if Connection.count_rows_in_partition(default_name, where_condition).zero?

      @executor.drain_rows_between_partitions!(
        default_name,
        staging_name,
        where_condition,
        conflict_key,
        cursor_columns: cursor_columns
      )
    end

    def staging_row_count(staging_name)
      return 0 unless Connection.partition_exists?(staging_name)

      Connection.count_rows_in_partition_table(staging_name)
    end

    def start_run_record(plan_signature)
      RunRecord.start(table_name: @config[:table_name], plan_signature: plan_signature)
    end

    def notify_resume(record)
      PartitionGardener.configuration.notify(
        "[PartitionGardener] Resuming rebalance for #{@config[:table_name]} at phase #{record.phase}",
        context: {
          table_name: @config[:table_name],
          job: @job_class_name,
          action: "resume",
          phase: record.phase,
          plan_signature: record.plan_signature
        }
      )
    end

    def notify_rebalance_complete(table_name, plan)
      PartitionGardener.configuration.notify(
        "[PartitionGardener] Rebalanced tail partitions for #{table_name}",
        context: {
          table_name: table_name,
          layout: @config.fetch(:layout, :sliding_window),
          segments: plan.segments.map(&:signature),
          hot_buckets: plan.hot_buckets,
          incremental: incremental_rebalance?
        }
      )
    end

    def analyze_parent_table!(table_name)
      return unless analyze_after_rebalance?

      Connection.connection.execute("ANALYZE #{Connection.quoted_table(table_name)}")
    end

    def analyze_after_rebalance?
      @config.fetch(:analyze_after_rebalance, PartitionGardener.configuration.analyze_after_rebalance)
    end
  end
end

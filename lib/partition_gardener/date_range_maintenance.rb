module PartitionGardener
  class DateRangeMaintenance
    include Naming

    def initialize(config, job_class_name: "PartitionGardener", executor: nil)
      @config = config
      @job_class_name = job_class_name
      @executor = executor || Executor.for_config(config)
    end

    def run!
      report_audit_warnings
      ensure_default_partition
      unless MaintenanceBackend.hybrid?(@config)
        finalize_archive_partitions
        apply_archive_retention!
      end
      rebalance_tail!
      drain_default_partition
    end

    def split_future_month_from_current!(_identifier = nil)
      rebalance_tail!
    end

    def split_pressured_future_month_partitions
      rebalance_tail!
    end

    def collapse_low_volume_future_month_partitions
      rebalance_tail!
    end

    private

    def strategy
      Strategy.for(@config)
    end

    def connection
      Connection.connection
    end

    def conflict_key
      @config[:conflict_key] || begin
        [@config[:partition_key_column].split("::").first.strip, "id"].uniq
      end
    end

    def cursor_columns
      strategy.cursor_columns
    end

    def table_name
      @config[:table_name]
    end

    def notify_error(error, action)
      PartitionGardener.configuration.notify(
        error,
        context: {
          table_name: table_name,
          job: @job_class_name,
          action: action
        }
      )
    end

    def rebalance_tail!
      return unless Connection.table_is_partitioned?(table_name)

      plan = strategy.build_plan
      PlanApplier.new(@config, executor: @executor, job_class_name: @job_class_name).apply!(plan)
    rescue => error
      notify_error(error, "rebalance_tail")
      raise
    end

    def ensure_default_partition
      DefaultPartition.ensure!(@config, executor: @executor)
    rescue => error
      notify_error(error, "ensure_default_partition")
      raise
    end

    def finalize_archive_partitions
      return unless Connection.table_is_partitioned?(table_name)
      return if strategy.is_a?(Strategy::HashBranches)
      return if strategy.is_a?(Strategy::ListSplit)
      return if strategy.is_a?(Strategy::IntegerRange)

      source_name = archive_finalize_source_partition_name
      return unless source_name
      return unless Connection.partition_exists?(source_name)

      Connection.get_distinct_partition_identifiers(
        source_name,
        @config[:partition_key_column],
        @config[:extract_partition_identifier]
      ).each do |identifier|
        next unless strategy.archive_bucket?(identifier)

        finalize_archive_from_source!(identifier, source_name)
      end
    rescue => error
      notify_error(error, "finalize_archive_partitions")
      raise
    end

    def archive_finalize_source_partition_name
      current_name = current_partition_name(table_name)
      return current_name if Connection.partition_exists?(current_name)

      default_partition_name(table_name) if Connection.partition_exists?(default_partition_name(table_name))
    end

    def finalize_archive_from_source!(identifier, source_partition_name)
      partition_name = archive_partition_name(identifier)
      where_condition = strategy.bucket_where_condition(identifier)

      ensure_archive_partition_attached!(identifier, partition_name: partition_name, source_partition_name: source_partition_name)

      record_count = Connection.count_rows_in_partition(source_partition_name, where_condition)
      return if record_count.zero?

      @executor.move_rows_to_parent_partition!(
        table_name: table_name,
        source_partition_name: source_partition_name,
        where_condition: where_condition,
        destination_partition_name: partition_name,
        conflict_key: conflict_key,
        record_count: record_count,
        cursor_columns: cursor_columns
      )
    end

    def archive_partition_name(identifier)
      if @config[:archive_partition_name_format]
        @config[:archive_partition_name_format].call(identifier)
      else
        @config[:partition_name_format].call(identifier)
      end
    end

    def drain_default_partition
      return unless Connection.table_is_partitioned?(table_name)

      default_name = default_partition_name(table_name)
      return unless Connection.partition_exists?(default_name)

      default_row_count = Connection.count_rows_in_partition_table(default_name)
      return if default_row_count.zero?

      PartitionGardener.configuration.notify(
        "[PartitionGardener] Found #{default_row_count} rows in #{default_name}",
        context: {
          table_name: table_name,
          default_partition_name: default_name,
          count: default_row_count
        }
      )

      unless strategy.is_a?(Strategy::HashBranches) || strategy.is_a?(Strategy::ListSplit)
        bucket_counts(default_name).each do |identifier, row_count|
          if strategy.archive_bucket?(identifier)
            finalize_archive_from_source!(identifier, default_name)
          elsif strategy.future_bucket?(identifier) && row_count >= split_row_threshold
            finalize_archive_from_source!(identifier, default_name)
          end
        end
      end

      skip_bucket_drain = strategy.is_a?(Strategy::HashBranches) || strategy.is_a?(Strategy::ListSplit)
      drain_remaining_default_rows!(known_row_count: skip_bucket_drain ? default_row_count : nil)
    rescue => error
      notify_error(error, "drain_default_partition")
      raise
    end

    def drain_remaining_default_rows!(known_row_count: nil)
      default_name = default_partition_name(table_name)
      where_condition = strategy.default_partition_drain_where_condition
      return if where_condition == "FALSE"

      record_count = known_row_count || Connection.count_rows_in_partition(default_name, where_condition)
      return if record_count.zero?

      @executor.move_rows_to_parent_partition!(
        table_name: table_name,
        source_partition_name: default_name,
        where_condition: where_condition,
        destination_partition_name: table_name,
        conflict_key: conflict_key,
        record_count: record_count,
        cursor_columns: cursor_columns
      )
    end

    def split_row_threshold
      @config.fetch(:split_row_threshold, FUTURE_MONTH_PARTITION_ROW_THRESHOLD)
    end

    def bucket_counts(partition_name)
      if strategy.is_a?(Strategy::DateRange)
        strategy.bucket_counts_in_partition(partition_name)
      else
        Connection.get_distinct_partition_identifiers(
          partition_name,
          @config[:partition_key_column],
          @config[:extract_partition_identifier]
        ).index_with do |identifier|
          Connection.count_rows_in_partition(partition_name, strategy.bucket_where_condition(identifier))
        end
      end
    end

    def ensure_archive_partition_attached!(identifier, partition_name:, source_partition_name:)
      for_values_clause = archive_for_values_clause(identifier)
      where_condition = strategy.bucket_where_condition(identifier)

      return if Connection.partition_attached?(table_name, partition_name)

      if Connection.count_rows_in_partition(source_partition_name, where_condition).positive?
        @executor.ensure_detached_partition_table!(table_name, partition_name, conflict_key: conflict_key)
        @executor.drain_rows_between_partitions!(
          source_partition_name,
          partition_name,
          where_condition,
          conflict_key,
          cursor_columns: cursor_columns
        )
      end

      if Connection.partition_exists?(partition_name)
        attach_archive_partition!(table_name, partition_name, for_values_clause, where_condition)
      else
        @executor.create_partition(table_name, partition_name, for_values_clause)
      end
    end

    def attach_archive_partition!(table_name, partition_name, for_values_clause, where_condition)
      @executor.attach_partition(table_name, partition_name, for_values_clause)
    rescue => error
      raise unless check_violation?(error)

      default_name = default_partition_name(table_name)
      if Connection.partition_exists?(default_name) &&
          Connection.count_rows_in_partition(default_name, where_condition).positive?
        @executor.drain_rows_between_partitions!(
          default_name,
          partition_name,
          where_condition,
          conflict_key,
          cursor_columns: cursor_columns
        )
      end

      @executor.attach_partition(table_name, partition_name, for_values_clause)
    end

    def check_violation?(error)
      message = error.message.to_s
      return true if message.include?("CheckViolation") || message.include?("check constraint")

      error.cause && check_violation?(error.cause)
    end

    def report_audit_warnings
      audit = Audit.call(table_name, config: @config)
      audit.warnings.each do |warning|
        PartitionGardener.configuration.notify(
          "[PartitionGardener] #{warning}",
          context: {
            table_name: table_name,
            job: @job_class_name,
            action: "audit"
          }
        )
      end
    end

    def apply_archive_retention!
      ArchiveRetention.new(@config, executor: @executor, job_class_name: @job_class_name).apply!
    end

    def archive_for_values_clause(identifier)
      if strategy.is_a?(Strategy::IntegerRange)
        band = @config.fetch(:archive_band_size, Strategy::IntegerRange::DEFAULT_ARCHIVE_BAND_SIZE)
        "FROM (#{identifier}) TO (#{identifier + band})"
      else
        @config[:partition_definition].call(identifier)
      end
    end
  end

  ThreeAreaMaintenance = DateRangeMaintenance
end

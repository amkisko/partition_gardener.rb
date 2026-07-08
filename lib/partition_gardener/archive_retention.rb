module PartitionGardener
  class ArchiveRetention
    include Naming

    def initialize(config, executor: nil, job_class_name: "PartitionGardener")
      @config = config
      @executor = executor || Executor.for_config(config)
      @job_class_name = job_class_name
    end

    def apply!(dry_run: nil)
      retention_months = @config[:retention_months]
      return 0 unless retention_months

      apply_retention = if dry_run.nil?
        @config.fetch(:retention_apply, false)
      else
        !dry_run
      end

      strategy = Strategy.for(@config)
      return 0 unless strategy.is_a?(Strategy::DateRange)

      table_name = @config[:table_name]
      cutoff = DateCalendar.add_months(PartitionGardener.configuration.today, -retention_months)
      dropped = 0
      managed_tail_names = managed_tail_name_set(strategy)

      Connection.attached_partitions(table_name).each do |partition|
        next if partition.default
        next if skip_retention_partition?(strategy, partition.name, managed_tail_names)

        bucket = strategy.archive_bucket_from_partition_name(partition.name)
        next unless bucket
        next if bucket >= DateCalendar.beginning_of_month(cutoff)

        if apply_retention
          @executor.detach_partition(table_name, partition.name, concurrently: detach_concurrently?)
          @executor.drop_table(partition.name) unless @config.fetch(:retention_keep_table, false)

          PartitionGardener.configuration.notify(
            "[PartitionGardener] Dropped archive partition #{partition.name} (retention #{retention_months} months)",
            context: {
              table_name: table_name,
              partition_name: partition.name,
              retention_months: retention_months,
              job: @job_class_name
            }
          )
          dropped += 1
          next
        end

        PartitionGardener.configuration.notify(
          "[PartitionGardener] Would drop archive partition #{partition.name} (bucket #{bucket}, retention #{retention_months} months)",
          context: {
            table_name: table_name,
            partition_name: partition.name,
            bucket: bucket,
            dry_run: true
          }
        )
        dropped += 1
      end

      dropped
    end

    private

    def detach_concurrently?
      @config.fetch(:retention_detach_concurrently, PartitionGardener.configuration.retention_detach_concurrently)
    end

    def managed_tail_name_set(strategy)
      Set.new(strategy.managed_tail_partition_names)
    rescue NoMethodError
      Set.new
    end

    def skip_retention_partition?(strategy, partition_name, managed_tail_names)
      (strategy.respond_to?(:tail_slot_name?) && strategy.tail_slot_name?(partition_name)) ||
        managed_tail_names.include?(partition_name)
    rescue NoMethodError
      false
    end
  end
end

module PartitionGardener
  class PremakeMonthlyMaintenance < DateRangeMaintenance
    def run!
      report_audit_warnings
      ensure_default_partition
      ensure_premade_months!
      apply_archive_retention!
      drain_default_partition
    end

    private

    def ensure_premade_months!
      return unless Connection.table_is_partitioned?(table_name)

      month_count = @config.fetch(:premake_months, 3)
      start_month = DateCalendar.beginning_of_month(PartitionGardener.configuration.today)

      (0..month_count).each do |offset|
        identifier = DateCalendar.add_months(start_month, offset)
        ensure_month_partition!(identifier)
      end
    end

    def ensure_month_partition!(identifier)
      partition_name = @config[:partition_name_format].call(identifier)
      for_values_clause = @config[:partition_definition].call(identifier)

      return if Connection.partition_attached?(table_name, partition_name)

      if Connection.partition_exists?(partition_name)
        send(
          :attach_archive_partition!,
          table_name,
          partition_name,
          for_values_clause,
          strategy.bucket_where_condition(identifier)
        )
      else
        @executor.create_partition(table_name, partition_name, for_values_clause)
      end
    end
  end
end

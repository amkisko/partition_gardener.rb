module PartitionGardener
  class Audit
    SCHEMA_VERSION = "1.0"
    HORIZON_WARNING_DAYS = 30

    AuditResult = Data.define(
      :table_name,
      :partitioned,
      :default_row_count,
      :attached_child_count,
      :horizon_days,
      :gaps,
      :warnings
    )

    def self.call(table_name, config: Registry.find_by_table_name(table_name))
      new(table_name, config: config).call
    end

    def initialize(table_name, config: nil)
      @table_name = table_name
      @config = config || Registry.find_by_table_name(table_name)
    end

    def call
      unless Connection.table_is_partitioned?(@table_name)
        return AuditResult.new(
          table_name: @table_name,
          partitioned: false,
          default_row_count: 0,
          attached_child_count: 0,
          horizon_days: nil,
          gaps: [],
          warnings: ["#{@table_name} is not a partitioned table"]
        )
      end

      default_name = Naming.default_partition_name(@table_name)
      default_row_count = if Connection.partition_exists?(default_name)
        Connection.count_rows_in_partition_table(default_name)
      else
        0
      end

      partitions = Connection.attached_partitions(@table_name)
      warnings = []
      warnings << "default partition #{default_name} has #{default_row_count} rows" if default_row_count.positive?
      warnings << "default partition #{default_name} is missing" unless Connection.partition_exists?(default_name)

      horizon_days = compute_horizon_days(partitions)
      if horizon_days && horizon_days < HORIZON_WARNING_DAYS
        warnings << "partition horizon is #{horizon_days} days ahead (below #{HORIZON_WARNING_DAYS})"
      end

      if partitions.size > 200
        warnings << "attached child count is #{partitions.size} (high catalog pressure)"
      end

      gaps = GapDetection.call(@table_name, config: @config)
      gaps.each do |gap|
        warnings << "partition gap: #{gap.message}"
      end

      AuditResult.new(
        table_name: @table_name,
        partitioned: true,
        default_row_count: default_row_count,
        attached_child_count: partitions.size,
        horizon_days: horizon_days,
        gaps: gaps,
        warnings: warnings
      )
    end

    private

    def compute_horizon_days(partitions)
      today = PartitionGardener.configuration.today
      finite_ends = partitions.filter_map do |partition|
        next if partition.default
        next if partition.range_end == :max
        next unless partition.range_end.is_a?(Date)

        partition.range_end
      end

      return nil if finite_ends.empty?

      max_end = finite_ends.max
      (max_end - today).to_i
    end
  end
end

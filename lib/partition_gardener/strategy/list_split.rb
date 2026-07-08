module PartitionGardener
  module Strategy
    class ListSplit
      include Naming
      include RequiresDefaultPartition
      include CursorColumns

      def initialize(config)
        @config = config
      end

      def active_window
        {start: nil, end: nil}
      end

      def build_plan
        segments = branches.map do |branch|
          Plan::Segment.new(
            name: branch_partition_name(branch),
            range_start: branch.fetch(:value),
            range_end: nil,
            kind: :branch
          )
        end

        Plan::Result.new(segments: segments, hot_buckets: [])
      end

      def attached_tail_segments
        Connection.attached_partitions(table_name).filter_map do |partition|
          next if partition.default

          branch = branch_for_partition_name(partition.name)
          next unless branch

          Plan::Segment.new(
            name: partition.name,
            range_start: branch.fetch(:value),
            range_end: nil,
            kind: :branch
          )
        end
      end

      def collect_heatmap(_window)
        {bucket_counts: {}, default_rows: default_row_count}
      end

      def hot_buckets_in_window(_heatmap, _window)
        []
      end

      def managed_tail_partition_names
        branches.map { |branch| branch_partition_name(branch) }
      end

      def tail_slot_name?(_partition_name)
        false
      end

      def current_and_future_where_condition(window: active_window)
        "TRUE"
      end

      def rebalance_default_drain_where_condition(window: active_window)
        "TRUE"
      end

      def bucket_where_condition(branch_value)
        branch = branches.find { |entry| entry.fetch(:value) == branch_value }
        branch.fetch(:where_condition)
      end

      def archive_bucket?(_bucket)
        false
      end

      def future_bucket?(_bucket)
        false
      end

      def archive_bucket_from_partition_name(partition_name)
        branch = branch_for_partition_name(partition_name)
        branch&.fetch(:value)
      end

      def segment_for_values_clause(segment)
        value = segment.range_start
        formatted = format_list_value(value)
        "IN (#{formatted})"
      end

      private

      def table_name
        @config[:table_name]
      end

      def branches
        @config.fetch(:branches)
      end

      def branch_partition_name(branch)
        "#{table_name}_#{branch.fetch(:name)}"
      end

      def branch_for_partition_name(partition_name)
        branches.find { |branch| branch_partition_name(branch) == partition_name }
      end

      def format_list_value(value)
        return "NULL" if value.nil?

        "'#{value}'"
      end

      def default_row_count
        default_name = default_partition_name(table_name)
        return 0 unless Connection.partition_exists?(default_name)

        Connection.count_rows_in_partition_table(default_name)
      end
    end
  end
end

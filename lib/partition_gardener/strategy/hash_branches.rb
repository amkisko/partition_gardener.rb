module PartitionGardener
  module Strategy
    class HashBranches
      include Naming
      include RequiresDefaultPartition
      include CursorColumns

      DEFAULT_MODULUS = 32

      def initialize(config)
        @config = config
      end

      def active_window
        {start: 0, end: modulus}
      end

      def build_plan
        heatmap = collect_heatmap(active_window)
        hot_buckets = hot_buckets_in_window(heatmap, active_window)

        segments = (0...modulus).map do |remainder|
          hot = hot_buckets.include?(remainder)
          Plan::Segment.new(
            name: hash_partition_name(remainder, hot: hot),
            range_start: {modulus: modulus, remainder: remainder},
            range_end: nil,
            kind: hot ? :hot_bucket : :archive
          )
        end

        Plan::Result.new(segments: segments, hot_buckets: hot_buckets)
      end

      def attached_tail_segments
        Connection.attached_partitions(table_name).filter_map do |partition|
          next if partition.default
          next unless hash_partition_name?(partition.name)

          remainder = hash_remainder_from_partition_name(partition.name)
          next if remainder.nil?

          hot = hot_bucket_partition_name?(partition.name)
          Plan::Segment.new(
            name: partition.name,
            range_start: {modulus: modulus, remainder: remainder},
            range_end: nil,
            kind: hot ? :hot_bucket : :archive
          )
        end
      end

      def collect_heatmap(_window)
        bucket_counts = HashRouting.collect_bucket_counts(@config)

        {bucket_counts: bucket_counts, default_rows: default_row_count}
      end

      def hot_buckets_in_window(heatmap, _window)
        heatmap[:bucket_counts].filter_map do |remainder, row_count|
          remainder if row_count >= split_row_threshold
        end.sort
      end

      def managed_tail_partition_names(window: active_window)
        Connection.attached_partitions(table_name).filter_map do |partition|
          next if partition.default
          next unless hash_partition_name?(partition.name)

          partition.name
        end
      end

      def tail_slot_name?(_partition_name)
        false
      end

      def current_and_future_where_condition(window: active_window)
        "FALSE"
      end

      def default_partition_required?
        false
      end

      def rebalance_default_drain_where_condition(window: active_window)
        "FALSE"
      end

      def default_partition_drain_where_condition(window: active_window)
        "TRUE"
      end

      def bucket_where_condition(_bucket)
        "TRUE"
      end

      def archive_bucket?(_bucket)
        false
      end

      def future_bucket?(_bucket)
        false
      end

      def archive_bucket_from_partition_name(partition_name)
        hash_remainder_from_partition_name(partition_name)
      end

      def segment_for_values_clause(segment)
        "WITH (modulus #{segment.range_start[:modulus]}, remainder #{segment.range_start[:remainder]})"
      end

      private

      def table_name
        @config[:table_name]
      end

      def connection
        Connection.connection
      end

      def modulus
        @config.fetch(:hash_modulus, DEFAULT_MODULUS)
      end

      def split_row_threshold
        threshold = @config[:split_row_threshold]
        threshold.nil? ? FUTURE_MONTH_PARTITION_ROW_THRESHOLD : threshold
      end

      def hash_partition_name(remainder, hot:)
        prefix = hot ? "h" : "a"
        format("#{table_name}_#{prefix}_%02d", remainder)
      end

      def hash_partition_name?(partition_name)
        partition_name.match?(/^#{Regexp.escape(table_name)}_[ha]_\d+$/)
      end

      def hot_bucket_partition_name?(partition_name)
        partition_name.match?(/^#{Regexp.escape(table_name)}_h_\d+$/)
      end

      def hash_remainder_from_partition_name(partition_name)
        match = partition_name.match(/^#{Regexp.escape(table_name)}_[ha]_(\d+)$/)
        return unless match

        match[1].to_i
      end

      def default_row_count
        default_name = default_partition_name(table_name)
        return 0 unless Connection.partition_exists?(default_name)

        Connection.count_rows_in_partition_table(default_name)
      end
    end
  end
end

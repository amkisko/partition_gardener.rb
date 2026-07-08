module PartitionGardener
  module Strategy
    class IntegerRange
      include Naming
      include RequiresDefaultPartition
      include CursorColumns

      DEFAULT_ACTIVE_ID_WIDTH = 10_000_000
      DEFAULT_CURRENT_BAND_SIZE = 1_000_000
      DEFAULT_ARCHIVE_BAND_SIZE = 10_000_000

      def initialize(config)
        @config = config
      end

      def active_window
        active_lo = @config.fetch(:active_id_lo) { 0 }
        active_hi = active_lo + active_id_width
        {start: active_lo, end: active_hi}
      end

      def build_plan
        window = active_window
        heatmap = collect_heatmap(window)
        hot_buckets = hot_buckets_in_window(heatmap, window)

        segments = Layout::ZoneSegments.build_filler_and_hot_segments(
          table_name: table_name,
          buckets: each_bucket_in_range(window[:start], window[:end]),
          hot_buckets: hot_buckets,
          active_start: window[:start],
          active_end: window[:end],
          hot_bucket_name: method(:hot_bucket_partition_name),
          bucket_end: ->(bucket) { [bucket + current_band_size, window[:end]].min }
        )

        Plan::Result.new(segments: segments, hot_buckets: hot_buckets)
      end

      def attached_tail_segments
        window = active_window

        Connection.attached_partitions(table_name).filter_map do |partition|
          next if partition.default
          next unless managed_tail_partition?(partition.name, window: window)

          Plan::Segment.new(
            name: partition.name,
            range_start: partition.range_start,
            range_end: partition.range_end,
            kind: segment_kind_for(partition.name, window: window)
          )
        end
      end

      def collect_heatmap(window)
        bucket_counts = Hash.new(0)
        dedicated_partition_counts = {}
        dedicated_partitions = hot_bucket_partitions_in_window(window).to_h

        heatmap_source_partitions(window).each do |partition_name|
          counts = counts_by_bucket_in_partition(partition_name, window)
          counts.each { |bucket, count| bucket_counts[bucket] += count }

          bucket = dedicated_partitions[partition_name]
          dedicated_partition_counts[bucket] = counts.values.sum if bucket
        end

        {
          bucket_counts: bucket_counts,
          default_rows: default_row_count,
          dedicated_partition_counts: dedicated_partition_counts
        }
      end

      def hot_buckets_in_window(heatmap, window)
        hot_buckets = Set.new

        heatmap[:bucket_counts].each do |bucket, row_count|
          next unless bucket_in_window?(bucket, window)
          next unless row_count >= split_row_threshold

          hot_buckets << bucket
        end

        dedicated_counts = heatmap.fetch(:dedicated_partition_counts, {})
        hot_bucket_partitions_in_window(window).each do |_partition_name, bucket|
          row_count = dedicated_counts[bucket]
          next if row_count.nil?

          if row_count >= split_row_threshold
            hot_buckets << bucket
          else
            hot_buckets.delete(bucket)
          end
        end

        hot_buckets.sort
      end

      def managed_tail_partition_names(window: active_window)
        Connection.attached_partitions(table_name).filter_map do |partition|
          next if partition.default
          next unless managed_tail_partition?(partition.name, window: window)

          partition.name
        end
      end

      def tail_slot_name?(partition_name)
        partition_name == current_partition_name(table_name) ||
          partition_name == open_partition_name(table_name) ||
          partition_name == future_partition_name(table_name) ||
          partition_name.match?(/^#{Regexp.escape(table_name)}_open_\d+$/)
      end

      def current_and_future_where_condition(window: active_window)
        partition_key_column = @config[:partition_key_column]
        "#{partition_key_column} >= #{window[:start]}"
      end

      def bucket_where_condition(bucket)
        partition_key_column = @config[:partition_key_column]
        end_range = bucket + current_band_size
        "#{partition_key_column} >= #{bucket} AND #{partition_key_column} < #{end_range}"
      end

      def archive_bucket?(bucket)
        bucket < active_window[:start]
      end

      def future_bucket?(bucket)
        bucket >= active_window[:end]
      end

      def archive_bucket_from_partition_name(partition_name)
        match = partition_name.match(/^#{Regexp.escape(table_name)}_ids_(\d+)_(\d+)$/)
        return unless match

        match[1].to_i
      end

      def segment_for_values_clause(segment)
        if segment.range_end == :max
          "FROM (#{segment.range_start}) TO (MAXVALUE)"
        else
          "FROM (#{segment.range_start}) TO (#{segment.range_end})"
        end
      end

      def hot_bucket_partition_name(bucket)
        end_range = [bucket + current_band_size, active_window[:end]].min
        "#{table_name}_ids_#{bucket}_#{end_range}"
      end

      def current_band_size
        @config.fetch(:current_band_size, DEFAULT_CURRENT_BAND_SIZE)
      end

      private

      def table_name
        @config[:table_name]
      end

      def connection
        Connection.connection
      end

      def active_id_width
        @config.fetch(:active_id_width, DEFAULT_ACTIVE_ID_WIDTH)
      end

      def split_row_threshold
        @config.fetch(:split_row_threshold, FUTURE_MONTH_PARTITION_ROW_THRESHOLD)
      end

      def each_bucket_in_range(range_start, range_end_exclusive)
        buckets = []
        cursor = range_start
        while cursor < range_end_exclusive
          buckets << cursor
          cursor += current_band_size
        end
        buckets
      end

      def bucket_in_window?(bucket, window)
        bucket >= window[:start] && bucket < window[:end]
      end

      def managed_tail_partition?(partition_name, window:)
        return true if tail_slot_name?(partition_name)

        bucket = archive_bucket_from_partition_name(partition_name)
        bucket && bucket_in_window?(bucket, window)
      end

      def segment_kind_for(partition_name, window:)
        return :future if partition_name == future_partition_name(table_name)
        return :filler if tail_slot_name?(partition_name)

        :hot_bucket
      end

      def heatmap_source_partitions(window)
        names = tail_slot_names_for_heatmap.select { |name| Connection.partition_attached?(table_name, name) }
        names.concat(hot_bucket_partitions_in_window(window).map(&:first))
        names.uniq
      end

      def tail_slot_names_for_heatmap
        [
          current_partition_name(table_name),
          open_partition_name(table_name),
          future_partition_name(table_name)
        ] + open_slot_partition_names
      end

      def open_slot_partition_names
        Connection.attached_partitions(table_name).map(&:name).select do |partition_name|
          partition_name.match?(/^#{Regexp.escape(table_name)}_open_\d+$/)
        end
      end

      def hot_bucket_partitions_in_window(window)
        Connection.attached_partitions(table_name).filter_map do |partition|
          bucket = archive_bucket_from_partition_name(partition.name)
          next unless bucket
          next unless bucket_in_window?(bucket, window)

          [partition.name, bucket]
        end
      end

      def counts_by_bucket_in_partition(partition_name, window)
        partition_key_column = @config[:partition_key_column]
        band = current_band_size

        sql = <<~SQL
          SELECT (#{connection.quote_column_name(partition_key_column)} / #{band}) * #{band} AS bucket,
                 COUNT(*)::int AS row_count
          FROM #{Connection.quoted_table(partition_name)}
          GROUP BY 1
        SQL

        connection.execute(sql).each_with_object({}) do |row, counts|
          bucket = row["bucket"].to_i
          counts[bucket] = row["row_count"].to_i if bucket_in_window?(bucket, window)
        end
      end

      def default_row_count
        default_name = default_partition_name(table_name)
        return 0 unless Connection.partition_exists?(default_name)

        Connection.count_rows_in_partition_table(default_name)
      end
    end
  end
end

module PartitionGardener
  module Strategy
    class DateRange
      include Naming
      include RequiresDefaultPartition
      include CursorColumns

      DEFAULT_ACTIVE_MONTHS = 12
      DEFAULT_ACTIVE_YEARS = 2

      def initialize(config)
        @config = config
      end

      def active_window
        bucket = date_bucket
        active_start = DateBucket.beginning_of_bucket(today, bucket)
        active_span = active_span_for(bucket)
        active_end = DateBucket.add_buckets(active_start, active_span, bucket)

        {start: active_start, end: active_end}
      end

      def build_plan
        window = active_window
        heatmap = collect_heatmap(window)
        hot_buckets = hot_buckets_in_window(heatmap, window)

        segments = if year_bucket?
          Layout::CalendarYear.build_segments(
            config: @config,
            active_start: window[:start],
            active_end: window[:end],
            hot_years: hot_buckets
          )
        else
          Layout::SlidingWindow.build_segments(
            config: @config,
            active_start: window[:start],
            active_end: window[:end],
            hot_months: hot_buckets
          )
        end

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
          counts = counts_by_bucket_in_partition(partition_name)
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
        return [] if rolling_current_layout?

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
        "#{partition_key_column} >= #{connection.quote(window[:start])}::date"
      end

      def bucket_where_condition(bucket)
        partition_key_column = @config[:partition_key_column]
        start_range = beginning_of_bucket(bucket)
        end_range = end_of_bucket(bucket)
        "#{partition_key_column} >= #{connection.quote(start_range)}::date AND #{partition_key_column} < #{connection.quote(end_range)}::date"
      end

      def archive_bucket?(bucket)
        beginning_of_bucket(bucket) < active_window[:start]
      end

      def future_bucket?(bucket)
        beginning_of_bucket(bucket) > beginning_of_bucket(today)
      end

      def archive_bucket_from_partition_name(partition_name)
        DateBucket.archive_bucket_from_partition_name(table_name, partition_name, date_bucket)
      end

      def segment_for_values_clause(segment)
        if segment.range_end == :max
          "FROM ('#{segment.range_start}') TO (MAXVALUE)"
        elsif segment.hash_partition?
          "WITH (modulus #{segment.range_start[:modulus]}, remainder #{segment.range_start[:remainder]})"
        else
          "FROM ('#{segment.range_start}') TO ('#{segment.range_end}')"
        end
      end

      def bucket_counts_in_partition(partition_name)
        counts_by_bucket_in_partition(partition_name)
      end

      private

      def table_name
        @config[:table_name]
      end

      def connection
        Connection.connection
      end

      def today
        PartitionGardener.configuration.today
      end

      def date_bucket
        DateBucket.normalize(@config.fetch(:bucket, :month))
      end

      def year_bucket?
        date_bucket == :year
      end

      def rolling_current_layout?
        @config.fetch(:layout, :sliding_window) == :rolling_current
      end

      def active_span_for(bucket)
        active_key = DateBucket.active_key(bucket)
        default = case bucket
        when :year then DEFAULT_ACTIVE_YEARS
        when :month then DEFAULT_ACTIVE_MONTHS
        else DateBucket.default_active_span(bucket)
        end
        @config.fetch(active_key, default)
      end

      def split_row_threshold
        @config.fetch(:split_row_threshold, FUTURE_MONTH_PARTITION_ROW_THRESHOLD)
      end

      def beginning_of_bucket(bucket)
        DateBucket.beginning_of_bucket(bucket.to_date, date_bucket)
      end

      def end_of_bucket(bucket)
        DateBucket.end_of_bucket(bucket.to_date, date_bucket)
      end

      def each_bucket_in_range(range_start, range_end_exclusive)
        buckets = []
        bucket = beginning_of_bucket(range_start)

        while bucket < range_end_exclusive
          buckets << bucket
          bucket = DateBucket.next_bucket(bucket, date_bucket)
        end

        buckets
      end

      def bucket_in_window?(bucket, window)
        return false if window[:start].nil? || window[:end].nil?

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

      def counts_by_bucket_in_partition(partition_name)
        partition_key_column = @config[:partition_key_column]
        trunc_unit = DateBucket.date_trunc_unit(date_bucket)
        bucket_expression = if partition_key_column.include?("::")
          "date_trunc('#{trunc_unit}', #{partition_key_column})::date"
        else
          "date_trunc('#{trunc_unit}', #{connection.quote_column_name(partition_key_column)})::date"
        end

        sql = <<~SQL
          SELECT #{bucket_expression} AS bucket, COUNT(*)::int AS row_count
          FROM #{Connection.quoted_table(partition_name)}
          GROUP BY 1
        SQL

        connection.execute(sql).each_with_object({}) do |row, counts|
          counts[Date.parse(row["bucket"].to_s)] = row["row_count"].to_i
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

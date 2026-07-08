module PartitionGardener
  module Layout
    class SlidingWindow
      class << self
        def active_end(active_start:, bucket: :month, active_span: nil)
          span = active_span || DateBucket.default_active_span(bucket)
          DateBucket.add_buckets(active_start, span, bucket)
        end

        def build_segments(config:, active_start:, active_end:, hot_months:)
          strategy = Strategy::DateRange.new(config)
          buckets = strategy.send(:each_bucket_in_range, active_start, active_end)
          bucket = config.fetch(:bucket, :month)

          ZoneSegments.build_filler_and_hot_segments(
            table_name: config[:table_name],
            buckets: buckets,
            hot_buckets: hot_months,
            active_start: active_start,
            active_end: active_end,
            hot_bucket_name: config[:partition_name_format],
            bucket_end: ->(bucket_start) { DateBucket.end_of_bucket(bucket_start, bucket) }
          )
        end
      end
    end
  end
end

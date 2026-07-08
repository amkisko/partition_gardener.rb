module PartitionGardener
  module Layout
    class IntegerWindow
      DEFAULT_ACTIVE_ID_WIDTH = Strategy::IntegerRange::DEFAULT_ACTIVE_ID_WIDTH

      class << self
        def active_end(active_start:, active_id_width: DEFAULT_ACTIVE_ID_WIDTH)
          active_start + active_id_width
        end

        def build_segments(config:, active_start:, active_end:, hot_buckets:)
          strategy = Strategy::IntegerRange.new(config)
          buckets = strategy.send(:each_bucket_in_range, active_start, active_end)

          ZoneSegments.build_filler_and_hot_segments(
            table_name: config[:table_name],
            buckets: buckets,
            hot_buckets: hot_buckets,
            active_start: active_start,
            active_end: active_end,
            hot_bucket_name: strategy.method(:hot_bucket_partition_name),
            bucket_end: ->(bucket) { [bucket + strategy.send(:current_band_size), active_end].min }
          )
        end
      end
    end
  end
end

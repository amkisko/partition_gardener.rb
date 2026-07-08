module PartitionGardener
  module Layout
    class CalendarYear
      DEFAULT_ACTIVE_YEARS = Strategy::DateRange::DEFAULT_ACTIVE_YEARS

      class << self
        def active_end(active_start:, active_years: DEFAULT_ACTIVE_YEARS)
          DateCalendar.add_years(active_start, active_years)
        end

        def build_segments(config:, active_start:, active_end:, hot_years:)
          strategy = Strategy::DateRange.new(config.merge(bucket: :year))
          buckets = strategy.send(:each_bucket_in_range, active_start, active_end)

          ZoneSegments.build_filler_and_hot_segments(
            table_name: config[:table_name],
            buckets: buckets,
            hot_buckets: hot_years,
            active_start: active_start,
            active_end: active_end,
            hot_bucket_name: config[:partition_name_format],
            bucket_end: ->(bucket) { DateCalendar.beginning_of_year(DateCalendar.next_year(bucket)) }
          )
        end
      end
    end
  end
end

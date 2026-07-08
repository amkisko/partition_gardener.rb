module PartitionGardener
  module Layout
    module ZoneSegments
      module_function

      def build_filler_and_hot_segments(table_name:, buckets:, hot_buckets:, active_start:, active_end:, hot_bucket_name:, bucket_end:)
        hot_bucket_set = hot_buckets.to_set
        segments = []
        middle_filler_index = 0
        index = 0

        while index < buckets.length
          bucket = buckets[index]

          if hot_bucket_set.include?(bucket)
            segments << Plan::Segment.new(
              name: hot_bucket_name.call(bucket),
              range_start: bucket,
              range_end: bucket_end.call(bucket),
              kind: :hot_bucket
            )
            index += 1
            next
          end

          run_start = bucket
          while index < buckets.length && !hot_bucket_set.include?(buckets[index])
            index += 1
          end
          run_end = (index < buckets.length) ? buckets[index] : active_end

          segment_name = if run_start == active_start
            Naming.current_partition_name(table_name)
          else
            middle_filler_index += 1
            if middle_filler_index == 1
              Naming.open_partition_name(table_name)
            else
              "#{table_name}_open_#{middle_filler_index}"
            end
          end

          segments << Plan::Segment.new(
            name: segment_name,
            range_start: run_start,
            range_end: run_end,
            kind: :filler
          )
        end

        segments << Plan::Segment.new(
          name: Naming.future_partition_name(table_name),
          range_start: active_end,
          range_end: :max,
          kind: :future
        )

        segments
      end
    end
  end
end

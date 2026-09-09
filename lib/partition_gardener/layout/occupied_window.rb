module PartitionGardener
  module Layout
    module OccupiedWindow
      module_function

      def plan_segments(config:, window:, hot_buckets:, year_bucket:, tail_slot:)
        occupied_segments = segments(table_name: config[:table_name], window: window, tail_slot: tail_slot)
        layout_kwargs = {
          config: config,
          active_start: window[:start],
          active_end: window[:end],
          occupied_segments: occupied_segments
        }

        if year_bucket
          CalendarYear.build_segments(**layout_kwargs, hot_years: hot_buckets)
        else
          SlidingWindow.build_segments(**layout_kwargs, hot_months: hot_buckets)
        end
      end

      def segments(table_name:, window:, tail_slot:)
        Connection.attached_partitions(table_name).filter_map do |partition|
          next if partition.default
          next if tail_slot.call(partition.name)
          next unless overlap?(partition, window)

          Plan::Segment.new(
            name: partition.name,
            range_start: partition.range_start,
            range_end: partition.range_end,
            kind: :hot_bucket
          )
        end.sort_by(&:range_start)
      end

      def overlap?(partition, window)
        return false unless partition.range_start.is_a?(Date)
        return false if partition.range_end.nil?
        return true if partition.range_end == :max
        return true if partition.range_end > window[:end]

        partition.range_start < window[:end] && partition.range_end > window[:start]
      end

      def covering(occupied_segments, bucket)
        occupied_segments.find do |segment|
          next false if segment.range_start > bucket

          segment.range_end == :max || segment.range_end > bucket
        end
      end

      def next_bucket_index(buckets, bound, from:)
        return buckets.length if bound == :max

        index = from
        index += 1 while index < buckets.length && buckets[index] < bound
        index
      end

      def finish_with_high_end(segments, occupied_segments:, table_name:, active_end:)
        leftover = occupied_segments.reject { |occupant| segments.any? { |segment| segment.name == occupant.name } }
        leftover.each { |occupant| segments << occupant }

        return segments if occupied_segments.any? { |segment| segment.range_end == :max }

        segments << Plan::Segment.new(
          name: Naming.future_partition_name(table_name),
          range_start: future_start(occupied_segments, active_end),
          range_end: :max,
          kind: :future
        )
        segments
      end

      def future_start(occupied_segments, active_end)
        later_ends = occupied_segments.filter_map do |segment|
          segment.range_end if segment.range_end.is_a?(Date) && segment.range_end > active_end
        end

        [active_end, *later_ends].max
      end
    end
  end
end

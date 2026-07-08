module PartitionGardener
  module Plan
    Segment = Data.define(:name, :range_start, :range_end, :kind) do
      def monthly?
        kind == :hot_bucket && !hash_partition?
      end

      def hot_bucket?
        kind == :hot_bucket
      end

      def filler?
        kind == :filler
      end

      def future?
        kind == :future
      end

      def archive?
        kind == :archive
      end

      def hash_partition?
        range_start.is_a?(Hash) && range_start.key?(:modulus)
      end

      def for_values_clause(strategy)
        strategy.segment_for_values_clause(self)
      end

      def signature
        [name, range_start, range_end, kind]
      end
    end

    Result = Data.define(:segments, :hot_buckets) do
      def hot_months
        hot_buckets
      end

      def changed?(attached_segments)
        attached_signatures = attached_segments.map(&:signature).sort
        target_signatures = segments.map(&:signature).sort
        attached_signatures != target_signatures
      end
    end
  end
end

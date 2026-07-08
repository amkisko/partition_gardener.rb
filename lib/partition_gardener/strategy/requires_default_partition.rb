module PartitionGardener
  module Strategy
    module RequiresDefaultPartition
      def default_partition_required?
        true
      end

      # Rows in default matching this condition are staged during tail rebalance.
      def rebalance_default_drain_where_condition(window: active_window)
        current_and_future_where_condition(window: window)
      end

      # Rows moved out of default at the end of maintenance (target: empty default).
      def default_partition_drain_where_condition(window: active_window)
        current_and_future_where_condition(window: window)
      end
    end
  end
end

module PartitionGardener
  module Layout
    # Every partitioning strategy targets the same three zones on the key axis:
    #
    #   archive  — coldest data; fine-grained children, retention-friendly, rarely written
    #   current  — hot active span; most reads/writes; may contain heat splits inside the zone
    #   future   — beyond the active window; sparse, less hot than current, not yet archived
    #
    # Strategy plugins (date range, integer range, hash) only define how keys map to bounds.
    # Heatmap collection and hot-bucket policy live on each strategy plugin.
    # Executor cursor moves are identical: ORDER BY partition_key, conflict_key — strategy-agnostic.
    module ThreeArea
      ZONES = %i[archive current future].freeze

      class << self
        def zone_slot_name(table_name, zone)
          case zone
          when :current then Naming.current_partition_name(table_name)
          when :future then Naming.future_partition_name(table_name)
          else
            raise ArgumentError, "archive zone uses strategy-specific bucket names, not a single slot"
          end
        end
      end
    end
  end
end

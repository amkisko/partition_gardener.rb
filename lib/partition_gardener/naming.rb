module PartitionGardener
  # Slot names for Layout::ThreeArea zones.
  # Archive buckets use strategy-specific names (YYYY_MM, id bands, hash remainder).
  module Naming
    module_function

    def current_partition_name(table_name)
      "#{table_name}_current"
    end

    def open_partition_name(table_name)
      "#{table_name}_open"
    end

    # Current-zone gap filler (after heat splits). Not a fourth zone.

    def future_partition_name(table_name)
      "#{table_name}_future"
    end

    def rebalance_staging_partition_name(table_name)
      "#{table_name}_rebalance_staging"
    end

    def default_partition_name(table_name)
      "#{table_name}_default"
    end
  end
end

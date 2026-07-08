module PartitionGardener
  module Strategy
    class << self
      def for(config)
        build(config)
      end

      def build(config)
        case config.fetch(:layout, :sliding_window)
        when :integer_window
          IntegerRange.new(config)
        when :hash_branches
          HashBranches.new(config)
        when :list_split
          ListSplit.new(config)
        when :calendar_year
          DateRange.new(config.merge(bucket: :year))
        when :premake_monthly, :rolling_current
          DateRange.new(config)
        else
          DateRange.new(config)
        end
      end
    end
  end
end

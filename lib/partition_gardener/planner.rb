module PartitionGardener
  class Planner
    def initialize(config)
      @config = config
    end

    def build
      strategy.build_plan
    end

    def attached_tail_segments
      strategy.attached_tail_segments
    end

    private

    def strategy
      Strategy.for(@config)
    end
  end
end

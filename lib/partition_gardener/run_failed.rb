module PartitionGardener
  class RunFailed < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super("Partition maintenance failed for #{errors.size} table(s)")
    end
  end
end

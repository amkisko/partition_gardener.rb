module PartitionGardener
  module IntegerDurationMethods
    def minutes
      self * 60
    end

    def seconds
      self
    end
  end
end

unless defined?(ActiveSupport::Duration)
  Integer.include(PartitionGardener::IntegerDurationMethods)
end

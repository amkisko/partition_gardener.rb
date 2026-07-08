module PartitionGardener
  module Blank
    module_function

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def present?(value)
      !blank?(value)
    end
  end
end

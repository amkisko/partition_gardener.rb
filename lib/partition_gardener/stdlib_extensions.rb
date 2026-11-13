module PartitionGardener
  module IntegerDurationMethods
    def minutes
      self * 60
    end

    def seconds
      self
    end
  end

  # Opt-in for non-ActiveSupport hosts (CLI/scripts). Rails apps already have Duration.
  def self.install_stdlib_extensions!
    return if defined?(ActiveSupport::Duration)
    return if Integer.included_modules.include?(IntegerDurationMethods)

    Integer.include(IntegerDurationMethods)
  end
end

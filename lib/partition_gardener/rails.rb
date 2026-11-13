module PartitionGardener
  class Railtie < Rails::Railtie
    config.partition_gardener = ActiveSupport::OrderedOptions.new
    # Requiring partition_gardener/railtie opts in; set false to load the railtie
    # without overwriting connection_resolver / today_resolver.
    config.partition_gardener.auto_configure = true

    initializer "partition_gardener.connection" do |app|
      next unless app.config.partition_gardener.auto_configure

      PartitionGardener.configure do |configuration|
        configuration.connection_resolver = -> { ActiveRecord::Base.connection }
        configuration.today_resolver = -> { Time.zone.today }
      end
    end
  end
end

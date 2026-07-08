require "rails"

module PartitionGardener
  class Railtie < Rails::Railtie
    initializer "partition_gardener.connection" do
      PartitionGardener.configure do |config|
        config.connection_resolver = -> { ActiveRecord::Base.connection }
        config.today_resolver = -> { Time.zone.today }
      end
    end
  end
end

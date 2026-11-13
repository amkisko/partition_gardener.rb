# Opt-in Rails integration. Host apps that want Active Record and Time.zone
# defaults should require this file (Gemfile require list or an initializer).
#
#   gem "partition_gardener", require: ["partition_gardener", "partition_gardener/railtie"]
#
# Or:
#
#   # config/application.rb / an initializer
#   require "partition_gardener/railtie"
#
require "rails/railtie"
require_relative "rails"

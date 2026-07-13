require "bundler/setup"

# When POLYRUN_RSPEC_JSON=1, each parallel worker writes tmp/rspec-<i>.json for CI report-junit.
if ENV["POLYRUN_RSPEC_JSON"] == "1" && ENV["POLYRUN_SHARD_INDEX"]
  require "fileutils"
  idx = ENV.fetch("POLYRUN_SHARD_INDEX")
  json_out = File.expand_path("../tmp/rspec-#{idx}.json", __dir__)
  FileUtils.mkdir_p(File.dirname(json_out))
  RSpec.configure do |config|
    config.add_formatter(:json, json_out)
  end
end

polyrun_cov_measure =
  ENV["POLYRUN_COVERAGE_DISABLE"] != "1" &&
  %w[1 true yes].include?(ENV["POLYRUN_COVERAGE"]&.to_s&.downcase)

if polyrun_cov_measure
  require "polyrun"
  Polyrun::Coverage::Rails.start!
end

require "partition_gardener"
require "pg"
require "active_support/time"

Dir[File.join(__dir__, "integration/support/**/*.rb")].sort.each { |path| require path }

RSpec.configure do |config|
  config.around do |example|
    Time.use_zone("UTC") { example.run }
  end

  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:integration] = true
  end

  config.before do
    PartitionGardener.reset_configuration!
    PartitionGardener::Registry.reset!
  end

  config.before(:each, :integration) do
    unless PartitionGardener::Integration::Database.enabled?
      skip "integration specs require INTEGRATION=1 and PostgreSQL (see DATABASE_URL)"
    end

    begin
      PartitionGardener::Integration::Database.connect!
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad => error
      skip "PostgreSQL not available for integration specs: #{error.class}: #{error.message}"
    end
  end

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
end

require "polyrun/rspec"
Polyrun::RSpec.install_sharded_formatter_compat!
Polyrun::RSpec.install_failure_fragments!
Polyrun::RSpec.install_worker_ping!
Polyrun::RSpec.install_example_debug!
Polyrun::RSpec.install_example_rails_logging!
Polyrun::RSpec.install_example_timeout!
Polyrun::RSpec.install_example_prosopite!
if %w[1 true yes].include?(ENV["POLYRUN_SPEC_QUALITY"]&.to_s&.downcase)
  Polyrun::RSpec.install_spec_quality!
end

require_relative "lib/partition_gardener/version"

Gem::Specification.new do |spec|
  spec.name = "partition_gardener"
  spec.version = PartitionGardener::VERSION
  spec.authors = ["Andrei Makarov"]
  spec.email = ["andrei@kiskolabs.com"]

  spec.summary = "Partition Gardener — PostgreSQL partition lifecycle maintenance"
  spec.description = "Runtime maintenance for PostgreSQL declarative partitions — archive / current / future zones, heat-driven splits, mandatory default drain, hot-switch migrations, and strategy templates."
  repository_url = "https://github.com/amkisko/partition_gardener.rb"
  spec.homepage = repository_url
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir[
      "lib/**/*",
      "exe/**/*",
      "sig/**/*",
      "docs/**/*",
      "README.md",
      "LICENSE.md",
      "CHANGELOG.md",
      "SECURITY.md"
    ].select { |path| File.file?(path) }
  end

  spec.require_paths = ["lib"]
  spec.executables = ["partition_gardener"]
  spec.bindir = "exe"

  repository_url = "https://github.com/amkisko/partition_gardener.rb"

  spec.metadata = {
    "homepage_uri" => repository_url,
    "source_code_uri" => repository_url,
    "changelog_uri" => "#{repository_url}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{repository_url}/issues",
    "documentation_uri" => "#{repository_url}#readme",
    "rubygems_mfa_required" => "true"
  }

  spec.add_dependency "pg", "~> 1.5"

  spec.add_development_dependency "activesupport", ">= 7.1"
  spec.add_development_dependency "activerecord", ">= 7.1"
  spec.add_development_dependency "rake", "~> 13"
  spec.add_development_dependency "rspec", "~> 3"
  spec.add_development_dependency "polyrun", ">= 2.2.0"
  spec.add_development_dependency "prosopite", "~> 2.0"
  spec.add_development_dependency "rspec_junit_formatter", "~> 0.6"
  spec.add_development_dependency "standard", "~> 1.52"
  spec.add_development_dependency "standard-custom", "~> 1.0"
  spec.add_development_dependency "standard-performance", "~> 1.8"
  spec.add_development_dependency "standard-rails", "~> 1.5"
  spec.add_development_dependency "standard-rspec", "~> 0.3"
  spec.add_development_dependency "rubocop-rails", "~> 2.33"
  spec.add_development_dependency "rubocop-rspec", "~> 3.8"
  spec.add_development_dependency "rubocop-thread_safety", "~> 0.7"
  spec.add_development_dependency "appraisal", "~> 2"
  spec.add_development_dependency "rbs", "~> 3"
end

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

namespace :spec do
  desc "Run PostgreSQL integration specs (INTEGRATION=1)"
  task :integration do
    ENV["INTEGRATION"] = "1"
    sh "bundle exec rspec spec/integration"
  end

  desc "Run unit and integration specs"
  task all: [:spec, :integration]
end

task default: :spec

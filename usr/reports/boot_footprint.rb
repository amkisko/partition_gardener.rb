#!/usr/bin/env ruby
# frozen_string_literal: true

# Read-only boot footprint report for partition_gardener.
# Usage: bundle exec ruby usr/reports/boot_footprint.rb

require "json"

def rss_kb
  `ps -o rss= -p #{Process.pid}`.to_i
rescue Errno::EPERM, Errno::ENOENT
  nil
end

def timed_require(label, &block)
  before_features = $LOADED_FEATURES.size
  before_rss = rss_kb
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  block.call
  elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
  after_features = $LOADED_FEATURES.size
  after_rss = rss_kb
  gardener = $LOADED_FEATURES.count { |path| path.include?("partition_gardener") }
  {
    label: label,
    ms: elapsed_ms.round(2),
    features_delta: after_features - before_features,
    rss_delta_kb: (before_rss && after_rss) ? after_rss - before_rss : nil,
    gardener_files: gardener
  }
end

runs = Integer(ENV.fetch("BOOT_RUNS", "10"), exception: false) || 10
samples = runs.times.map do
  cmd = <<~RUBY
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    require "partition_gardener"
    elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
    features = $LOADED_FEATURES.select { |path| path.include?("partition_gardener") }
    payload = {
      ms: elapsed.round(3),
      gardener_files: features.size,
      cli: features.any? { |path| path.end_with?("/cli.rb") },
      hot_switch: features.any? { |path| path.end_with?("/hot_switch_concern.rb") },
      railtie: features.any? { |path| path.end_with?("/railtie.rb") || path.end_with?("/rails.rb") },
      stdlib_extensions: features.any? { |path| path.end_with?("/stdlib_extensions.rb") }
    }
    puts payload.to_json
  RUBY
  output = IO.popen(["bundle", "exec", "ruby", "-e", cmd], chdir: File.expand_path("../..", __dir__), &:read)
  JSON.parse(output.lines.last)
end

ms_values = samples.map { |sample| sample.fetch("ms") }
summary = {
  runs: runs,
  mean_ms: (ms_values.sum / ms_values.size).round(2),
  min_ms: ms_values.min.round(2),
  max_ms: ms_values.max.round(2),
  gardener_files: samples.first.fetch("gardener_files"),
  side_paths_loaded: samples.first.slice("cli", "hot_switch", "railtie", "stdlib_extensions")
}

puts JSON.pretty_generate(summary)

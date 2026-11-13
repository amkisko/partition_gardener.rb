require "json"
require "open3"

RSpec.describe "partition_gardener boot footprint" do
  def run_snippet(code)
    output, error, status = Open3.capture3(
      {"BUNDLE_GEMFILE" => File.expand_path("../../Gemfile", __dir__)},
      "bundle", "exec", "ruby", "-e", code,
      chdir: File.expand_path("../..", __dir__)
    )
    raise "boot snippet failed (#{status.exitstatus}): #{error}\n#{output}" unless status.success?

    JSON.parse(output.lines.last)
  end

  it "does not load CLI, HotSwitch, Railtie, or Integer duration patch on default require" do
    snapshot = run_snippet(<<~RUBY)
      require "json"
      require "partition_gardener"
      # Checkout path contains "partition_gardener"; count only this gem's lib files.
      features = $LOADED_FEATURES.select { |path| path.match?(%r{(?:/|^)lib/partition_gardener(?:[.]rb|/)}) }
      puts({
        gardener_files: features.size,
        cli: features.any? { |path| path.end_with?("/cli.rb") },
        hot_switch: features.any? { |path| path.end_with?("/hot_switch_concern.rb") },
        railtie: features.any? { |path| path.end_with?("/railtie.rb") || path.end_with?("/rails.rb") },
        stdlib_extensions: features.any? { |path| path.end_with?("/stdlib_extensions.rb") },
        integer_duration: Integer.included_modules.any? { |mod| mod.name&.include?("IntegerDuration") },
        cli_constant: defined?(PartitionGardener::CLI),
        hot_switch_constant: defined?(PartitionGardener::Migration::HotSwitchConcern)
      }.to_json)
    RUBY

    expect(snapshot.fetch("cli")).to be(false)
    expect(snapshot.fetch("hot_switch")).to be(false)
    expect(snapshot.fetch("railtie")).to be(false)
    expect(snapshot.fetch("stdlib_extensions")).to be(false)
    expect(snapshot.fetch("integer_duration")).to be(false)
    expect(snapshot.fetch("cli_constant")).to be_nil
    expect(snapshot.fetch("hot_switch_constant")).to be_nil
    expect(snapshot.fetch("gardener_files")).to be < 55
  end

  it "loads side paths only when required explicitly" do
    snapshot = run_snippet(<<~RUBY)
      require "json"
      require "partition_gardener"
      require "partition_gardener/cli"
      require "partition_gardener/migration/hot_switch_concern"
      require "partition_gardener/stdlib_extensions"
      PartitionGardener.install_stdlib_extensions!
      puts({
        cli_constant: defined?(PartitionGardener::CLI),
        hot_switch_constant: defined?(PartitionGardener::Migration::HotSwitchConcern),
        integer_duration: Integer.included_modules.any? { |mod| mod.name&.include?("IntegerDuration") }
      }.to_json)
    RUBY

    expect(snapshot.fetch("cli_constant")).to eq("constant")
    expect(snapshot.fetch("hot_switch_constant")).to eq("constant")
    expect(snapshot.fetch("integer_duration")).to be(true)
  end
end

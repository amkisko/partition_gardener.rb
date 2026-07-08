require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe PartitionGardener::ConfigDocument do
  it "exports portable keys only" do
    config = PartitionGardener::Templates.sliding_window_monthly(
      table_name: "events",
      partition_key_column: "occurred_on",
      conflict_key: %w[id occurred_on],
      active_months: 6,
      retention_months: 12
    )

    document = described_class.export(config)

    expect(document).to include(
      table_name: "events",
      layout: :sliding_window,
      active_months: 6,
      retention_months: 12
    )
    expect(document).not_to have_key(:partition_name_format)
  end

  it "round-trips through JSON registry file" do
    path = File.join(Dir.tmpdir, "partition_registry_#{Process.pid}.json")
    File.write(
      path,
      JSON.generate(
        [
          {
            "table_name" => "events",
            "layout" => "sliding_window",
            "partition_key_column" => "occurred_on",
            "conflict_key" => %w[id occurred_on],
            "active_months" => 6
          }
        ]
      )
    )

    described_class.load_registry_file!(path)

    config = PartitionGardener::Registry.find_by_table_name("events")
    expect(config[:table_name]).to eq("events")
    expect(config[:active_months]).to eq(6)
  ensure
    File.delete(path) if File.exist?(path)
  end

  it "rejects registry entries with unsupported keys" do
    expect {
      described_class.validate_registry_document!(
        "table_name" => "events",
        "layout" => "sliding_window",
        "partition_key_column" => "occurred_on",
        "conflict_key" => %w[id occurred_on],
        "unknown_option" => true
      )
    }.to raise_error(ArgumentError, /unsupported keys: unknown_option/)
  end

  it "rejects layouts that require Ruby registration" do
    expect {
      described_class.validate_registry_document!(
        "table_name" => "events",
        "layout" => "composite",
        "partition_key_column" => "occurred_on",
        "conflict_key" => %w[id occurred_on]
      )
    }.to raise_error(ArgumentError, /layout "composite" is not supported in JSON import/)
  end
end

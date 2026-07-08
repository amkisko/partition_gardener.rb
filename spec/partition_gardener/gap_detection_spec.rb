require "spec_helper"

RSpec.describe PartitionGardener::GapDetection do
  let(:config) do
    PartitionGardener::Templates.sliding_window_monthly(
      table_name: "events",
      partition_key_column: "created_at",
      conflict_key: %w[created_at id]
    )
  end

  before do
    PartitionGardener::Registry.register(config)
    PartitionGardener.configure do |configuration|
      configuration.today_resolver = -> { Date.new(2026, 7, 5) }
    end
  end

  it "reports uncovered ranges between tail segments" do
    allow(PartitionGardener::Connection).to receive(:attached_partitions).with("events").and_return(
      [
        PartitionGardener::Connection::AttachedPartition.new(
          name: "events_current",
          range_start: Date.new(2026, 7, 1),
          range_end: Date.new(2026, 10, 1),
          default: false,
          list_values: nil
        ),
        PartitionGardener::Connection::AttachedPartition.new(
          name: "events_future",
          range_start: Date.new(2027, 1, 1),
          range_end: :max,
          default: false,
          list_values: nil
        )
      ]
    )

    gaps = described_class.call("events", config: config)

    expect(gaps.size).to eq(1)
    expect(gaps.first.message).to include("events_current")
    expect(gaps.first.message).to include("events_future")
  end
end

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

  it "orders integer bounds numerically instead of lexicographically" do
    integer_config = PartitionGardener::Templates.integer_window(
      table_name: "events",
      partition_key_column: "id",
      conflict_key: %w[id],
      active_id_lo: 0,
      active_id_width: 20_000_000,
      current_band_size: 1_000_000
    )
    strategy = PartitionGardener::Strategy::IntegerRange.new(integer_config)
    allow(PartitionGardener::Strategy).to receive(:for).with(integer_config).and_return(strategy)
    allow(strategy).to receive(:attached_tail_segments).and_return(
      [
        PartitionGardener::Plan::Segment.new(
          name: "events_ids_10000000_11000000",
          range_start: 10_000_000,
          range_end: 11_000_000,
          kind: :hot_bucket
        ),
        PartitionGardener::Plan::Segment.new(
          name: "events_ids_2000000_3000000",
          range_start: 2_000_000,
          range_end: 3_000_000,
          kind: :hot_bucket
        ),
        PartitionGardener::Plan::Segment.new(
          name: "events_future",
          range_start: 20_000_000,
          range_end: :max,
          kind: :future
        )
      ]
    )

    gaps = described_class.call("events", config: integer_config)
    messages = gaps.map(&:message)

    expect(messages).to include(a_string_matching(/events_ids_2000000_3000000 and events_ids_10000000_11000000/))
    expect(messages).not_to include(a_string_matching(/events_ids_10000000_11000000 and events_ids_2000000_3000000/))
  end
end

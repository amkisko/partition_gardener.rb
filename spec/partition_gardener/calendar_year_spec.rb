require "spec_helper"

RSpec.describe PartitionGardener::Layout::CalendarYear do
  let(:config) do
    PartitionGardener::Templates.calendar_year(
      table_name: "events",
      partition_key_column: "occurred_on",
      conflict_key: %w[id occurred_on],
      active_years: 2
    )
  end

  let(:active_start) { Date.new(2026, 1, 1) }
  let(:active_end) { Date.new(2028, 1, 1) }

  it "builds current and future year segments when no year is hot" do
    segments = described_class.build_segments(
      config: config,
      active_start: active_start,
      active_end: active_end,
      hot_years: []
    )

    expect(segments.map(&:name)).to eq(%w[events_current events_future])
    expect(segments.first.range_start).to eq(active_start)
    expect(segments.first.range_end).to eq(active_end)
  end
end

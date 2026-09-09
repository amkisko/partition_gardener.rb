require "spec_helper"

RSpec.describe PartitionGardener::Strategy::DateRange do
  let(:today) { Date.new(2026, 9, 9) }
  let(:config) do
    PartitionGardener::Templates.sliding_window_monthly(
      table_name: "events",
      partition_key_column: "occurred_on",
      conflict_key: %w[id occurred_on],
      active_months: 12
    )
  end
  let(:strategy) { described_class.new(config) }

  def attached(*partitions)
    allow(PartitionGardener::Connection).to receive(:attached_partitions).with("events").and_return(partitions)
  end

  def child(name, range_start, range_end = range_start.next_month, default: false)
    PartitionGardener::Connection::AttachedPartition.new(
      name: name,
      range_start: range_start,
      range_end: range_end,
      default: default,
      list_values: nil
    )
  end

  before do
    PartitionGardener.configure do |configuration|
      configuration.today_resolver = -> { today }
    end
    allow(strategy).to receive(:collect_heatmap).and_return(
      bucket_counts: {},
      default_rows: 0,
      dedicated_partition_counts: {}
    )
  end

  it "fills the remainder as open after a monthly child that already covers the window start" do
    attached(
      child("events_default", nil, nil, default: true),
      child("events_2026_08_01", Date.new(2026, 8, 1)),
      child("events_2026_09_01", Date.new(2026, 9, 1))
    )

    plan = strategy.build_plan
    open_filler = plan.segments.find { |segment| segment.name == "events_open" }
    september = plan.segments.find { |segment| segment.name == "events_2026_09_01" }

    expect(september.range_start).to eq(Date.new(2026, 9, 1))
    expect(september.range_end).to eq(Date.new(2026, 10, 1))
    expect(open_filler.range_start).to eq(Date.new(2026, 10, 1))
    expect(open_filler.range_end).to eq(Date.new(2027, 9, 1))
    expect(plan.segments.map(&:name)).to eq(%w[events_2026_09_01 events_open events_future])
  end

  it "fills the remainder as open after a default-named monthly child at the window start" do
    attached(
      child("events_default", nil, nil, default: true),
      child("events_2026_09", Date.new(2026, 9, 1))
    )

    open_filler = strategy.build_plan.segments.find { |segment| segment.name == "events_open" }

    expect(open_filler.range_start).to eq(Date.new(2026, 10, 1))
  end

  it "keeps a full-window current partition when no monthly child occupies the start" do
    attached(
      child("events_default", nil, nil, default: true),
      child("events_current", Date.new(2026, 9, 1), Date.new(2027, 9, 1)),
      child("events_future", Date.new(2027, 9, 1), :max)
    )

    plan = strategy.build_plan
    current = plan.segments.find { |segment| segment.name == "events_current" }

    expect(plan.segments.map(&:name)).to eq(%w[events_current events_future])
    expect(current.range_start).to eq(Date.new(2026, 9, 1))
    expect(current.range_end).to eq(Date.new(2027, 9, 1))
  end

  it "treats an occupying monthly child as managed tail so rebalance keeps it" do
    attached(
      child("events_default", nil, nil, default: true),
      child("events_2026_09_01", Date.new(2026, 9, 1))
    )

    names = strategy.attached_tail_segments.map(&:name)

    expect(names).to include("events_2026_09_01")
  end

  it "starts future after a premade month that begins at the window end" do
    attached(
      child("events_default", nil, nil, default: true),
      child("events_2026_09_01", Date.new(2026, 9, 1)),
      child("events_2027_09_01", Date.new(2027, 9, 1))
    )

    plan = strategy.build_plan
    future = plan.segments.find { |segment| segment.name == "events_future" }

    expect(plan.segments.map(&:name)).to eq(%w[events_2026_09_01 events_open events_2027_09_01 events_future])
    expect(future.range_start).to eq(Date.new(2027, 10, 1))
    expect(future.range_end).to eq(:max)
  end

  it "starts future after an occupant that straddles the window end" do
    attached(
      child("events_default", nil, nil, default: true),
      child("events_wide", Date.new(2026, 9, 1), Date.new(2027, 12, 1))
    )

    plan = strategy.build_plan
    future = plan.segments.find { |segment| segment.name == "events_future" }

    expect(plan.segments.map(&:name)).to eq(%w[events_wide events_future])
    expect(future.range_start).to eq(Date.new(2027, 12, 1))
  end

  it "does not plan future when an occupant already ends at MAXVALUE" do
    attached(
      child("events_default", nil, nil, default: true),
      child("events_overflow", Date.new(2027, 9, 1), :max)
    )

    plan = strategy.build_plan

    expect(plan.segments.map(&:name)).to eq(%w[events_current events_overflow])
  end

  it "keeps noncontiguous premade months past the window and starts future after the last of them" do
    attached(
      child("events_default", nil, nil, default: true),
      child("events_2027_10_01", Date.new(2027, 10, 1)),
      child("events_2027_12_01", Date.new(2027, 12, 1))
    )

    plan = strategy.build_plan
    future = plan.segments.find { |segment| segment.name == "events_future" }

    expect(plan.segments.map(&:name)).to eq(%w[events_current events_2027_10_01 events_2027_12_01 events_future])
    expect(future.range_start).to eq(Date.new(2028, 1, 1))
  end

  it "treats a premade month at the window end as managed tail" do
    attached(
      child("events_default", nil, nil, default: true),
      child("events_2027_09_01", Date.new(2027, 9, 1))
    )

    names = strategy.attached_tail_segments.map(&:name)

    expect(names).to include("events_2027_09_01")
  end
end

require "spec_helper"

RSpec.describe PartitionGardener::PlanDiff do
  let(:segment) do
    ->(name, start_date, end_date, kind = :filler) {
      PartitionGardener::Plan::Segment.new(
        name: name,
        range_start: start_date,
        range_end: end_date,
        kind: kind
      )
    }
  end

  it "marks unchanged segments as keep" do
    attached = [segment.call("events_current", Date.new(2026, 7, 1), Date.new(2027, 7, 1))]
    target = attached.dup

    operations = described_class.operations(attached, target)

    expect(operations.map(&:action)).to eq([:keep])
  end

  it "detects create, reshape, and drop operations" do
    attached = [
      segment.call("events_current", Date.new(2026, 7, 1), Date.new(2027, 7, 1)),
      segment.call("events_future", Date.new(2027, 7, 1), :max, :future)
    ]
    target = [
      segment.call("events_current", Date.new(2026, 7, 1), Date.new(2026, 9, 1)),
      segment.call("events_2026_09", Date.new(2026, 9, 1), Date.new(2026, 10, 1), :hot_bucket),
      segment.call("events_future", Date.new(2027, 7, 1), :max, :future)
    ]

    operations = described_class.operations(attached, target)

    expect(operations.map(&:action)).to contain_exactly(:reshape, :create, :keep)
  end
end

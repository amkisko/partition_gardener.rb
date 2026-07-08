require "spec_helper"

RSpec.describe PartitionGardener::Layout::SlidingWindow do
  let(:config) do
    {
      table_name: "user_workdays",
      partition_name_format: ->(identifier) { "user_workdays_#{identifier.strftime("%Y_%m")}" }
    }
  end

  let(:active_start) { Date.new(2026, 7, 1) }
  let(:active_end) { Date.new(2027, 7, 1) }

  def build_segments(hot_months)
    described_class.build_segments(
      config: config,
      active_start: active_start,
      active_end: active_end,
      hot_months: hot_months
    )
  end

  it "builds a single current segment and future tail when no month is hot" do
    segments = build_segments([])

    expect(segments.map(&:name)).to eq(%w[user_workdays_current user_workdays_future])
    expect(segments.first.range_start).to eq(active_start)
    expect(segments.first.range_end).to eq(active_end)
    expect(segments.last.range_end).to eq(:max)
  end

  it "splits a hot month and fills gaps with current, open, and future segments" do
    hot_months = [Date.new(2026, 9, 1), Date.new(2026, 12, 1)]
    segments = build_segments(hot_months)

    expect(segments.map(&:name)).to eq(
      %w[
        user_workdays_current
        user_workdays_2026_09
        user_workdays_open
        user_workdays_2026_12
        user_workdays_open_2
        user_workdays_future
      ]
    )
    expect(segments.map { |segment| [segment.range_start, segment.range_end] }).to eq(
      [
        [Date.new(2026, 7, 1), Date.new(2026, 9, 1)],
        [Date.new(2026, 9, 1), Date.new(2026, 10, 1)],
        [Date.new(2026, 10, 1), Date.new(2026, 12, 1)],
        [Date.new(2026, 12, 1), Date.new(2027, 1, 1)],
        [Date.new(2027, 1, 1), Date.new(2027, 7, 1)],
        [Date.new(2027, 7, 1), :max]
      ]
    )
  end
end

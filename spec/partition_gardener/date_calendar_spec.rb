require "spec_helper"

RSpec.describe PartitionGardener::DateCalendar do
  it "advances years through leap days without raising" do
    expect(described_class.add_years(Date.new(2024, 2, 29), 1)).to eq(Date.new(2025, 2, 28))
  end

  it "adds months from the beginning of the month" do
    expect(described_class.add_months(Date.new(2026, 1, 31), 1)).to eq(Date.new(2026, 2, 1))
  end
end

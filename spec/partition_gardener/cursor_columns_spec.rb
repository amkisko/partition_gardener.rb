require "spec_helper"

RSpec.describe PartitionGardener::Strategy::CursorColumns do
  let(:strategy) do
    PartitionGardener::Strategy::DateRange.new(
      table_name: "events",
      partition_key_column: "occurred_on",
      conflict_key: %w[id occurred_on]
    )
  end

  it "orders cursor columns with partition key first" do
    expect(strategy.cursor_columns).to eq(%w[occurred_on id])
  end
end

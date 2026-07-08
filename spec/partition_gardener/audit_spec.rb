require "spec_helper"

RSpec.describe PartitionGardener::Audit do
  let(:table_name) { "events" }
  let(:today) { Date.new(2026, 7, 5) }

  before do
    PartitionGardener.configure do |configuration|
      configuration.today_resolver = -> { today }
    end
  end

  it "reports when the table is not partitioned" do
    allow(PartitionGardener::Connection).to receive(:table_is_partitioned?).with(table_name).and_return(false)

    result = described_class.call(table_name)

    expect(result.partitioned).to be(false)
    expect(result.warnings).to include("events is not a partitioned table")
  end

  it "warns when default partition has rows" do
    allow(PartitionGardener::Connection).to receive(:table_is_partitioned?).with(table_name).and_return(true)
    allow(PartitionGardener::Connection).to receive(:partition_exists?).with("events_default").and_return(true)
    allow(PartitionGardener::Connection).to receive(:count_rows_in_partition_table).with("events_default").and_return(42)
    allow(PartitionGardener::Connection).to receive(:attached_partitions).with(table_name).and_return([])

    result = described_class.call(table_name)

    expect(result.default_row_count).to eq(42)
    expect(result.warnings).to include("default partition events_default has 42 rows")
  end

  it "warns when partition horizon is below 30 days" do
    allow(PartitionGardener::Connection).to receive(:table_is_partitioned?).with(table_name).and_return(true)
    allow(PartitionGardener::Connection).to receive(:partition_exists?).with("events_default").and_return(true)
    allow(PartitionGardener::Connection).to receive(:count_rows_in_partition_table).with("events_default").and_return(0)
    allow(PartitionGardener::Connection).to receive(:attached_partitions).with(table_name).and_return(
      [
        double(default: false, range_end: Date.new(2026, 7, 20))
      ]
    )

    result = described_class.call(table_name)

    expect(result.horizon_days).to eq(15)
    expect(result.warnings).to include("partition horizon is 15 days ahead (below 30)")
  end
end

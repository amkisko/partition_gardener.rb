require "spec_helper"

RSpec.describe PartitionGardener::PlanReport do
  let(:config) do
    PartitionGardener::Templates.sliding_window_monthly(
      table_name: "events",
      partition_key_column: "created_at",
      conflict_key: %w[created_at id]
    )
  end

  before do
    PartitionGardener.configure do |configuration|
      configuration.today_resolver = -> { Date.new(2026, 7, 5) }
    end
    allow(PartitionGardener::Connection).to receive_messages(attached_partitions: [], partition_attached?: false, partition_exists?: false, count_rows_in_partition_table: 0, count_rows_in_partition: 0)
  end

  it "serializes plan operations to JSON" do
    report = described_class.build(config)
    payload = JSON.parse(report.to_json)

    expect(payload["table_name"]).to eq("events")
    expect(payload["layout"]).to eq("sliding_window")
    expect(payload["operations"]).to be_an(Array)
    expect(payload["target_segments"]).not_to be_empty
  end
end

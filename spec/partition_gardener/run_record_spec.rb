require "spec_helper"

RSpec.describe PartitionGardener::RunRecord do
  let(:store) { PartitionGardener::MemoryRunRecordStore.new }

  before do
    PartitionGardener.configure do |configuration|
      configuration.run_record_store = store
    end
  end

  it "persists phase checkpoints" do
    record = described_class.start(table_name: "events", plan_signature: "abc123")
    record = record.advance!("segments")

    loaded = described_class.load("events")

    expect(loaded.phase).to eq("segments")
    expect(loaded.plan_signature).to eq("abc123")
  end

  it "clears stored records" do
    described_class.start(table_name: "events", plan_signature: "abc123")
    described_class.clear("events")

    expect(described_class.load("events")).to be_nil
  end
end

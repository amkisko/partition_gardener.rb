require "spec_helper"

RSpec.describe PartitionGardener::Connection do
  let(:connection) { double("connection", quote: "'public'") }

  before do
    allow(PartitionGardener.configuration).to receive_messages(connection: connection, schema_name: "public")
    described_class.clear_attached_partitions_cache!
  end

  it "memoizes attached_partitions per table within a cache scope" do
    allow(connection).to receive(:execute).and_return([])

    described_class.attached_partitions("events")
    described_class.attached_partitions("events")

    expect(connection).to have_received(:execute).once
  end

  it "clears memoized attached_partitions" do
    allow(connection).to receive(:execute).and_return([])

    described_class.attached_partitions("events")
    described_class.clear_attached_partitions_cache!
    described_class.attached_partitions("events")

    expect(connection).to have_received(:execute).twice
  end
end

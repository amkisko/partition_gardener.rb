require "spec_helper"

RSpec.describe PartitionGardener::Connection do
  let(:connection) { double("connection") }

  before do
    allow(PartitionGardener.configuration).to receive_messages(connection: connection, schema_name: "public")
    allow(connection).to receive(:quote) { |value| "'#{value}'" }
  end

  describe ".unique_index_covers?" do
    it "returns true when an index column prefix matches the conflict key" do
      allow(connection).to receive(:execute).and_return(
        [{"column_names" => "{id,occurred_on}"}]
      )

      expect(described_class.unique_index_covers?("events", %w[id occurred_on])).to be(true)
    end

    it "returns false when no index matches the conflict key" do
      allow(connection).to receive(:execute).and_return(
        [{"column_names" => "{id}"}]
      )

      expect(described_class.unique_index_covers?("events", %w[id occurred_on])).to be(false)
    end
  end
end

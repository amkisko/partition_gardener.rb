require "spec_helper"

RSpec.describe PartitionGardener::HashRouting do
  let(:config) do
    PartitionGardener::Templates.hash_branches(
      table_name: "packages",
      partition_key_column: "workspace_id",
      conflict_key: %w[workspace_id id],
      hash_modulus: 4
    )
  end

  it "counts rows from attached hash partitions without hashtext grouping" do
    allow(PartitionGardener::Connection).to receive(:attached_partitions).with("packages").and_return(
      [
        PartitionGardener::Connection::AttachedPartition.new(
          name: "packages_h_01",
          range_start: {modulus: 4, remainder: 1},
          range_end: nil,
          default: false,
          list_values: nil
        )
      ]
    )
    allow(PartitionGardener::Connection).to receive_messages(partition_exists?: false, partition_attached?: true)
    allow(PartitionGardener::Connection).to receive(:count_rows_in_partition_table).with("packages_h_01").and_return(42)

    counts = described_class.collect_bucket_counts(config)

    expect(counts).to eq({1 => 42})
  end
end

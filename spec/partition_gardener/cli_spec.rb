require "spec_helper"

RSpec.describe PartitionGardener::CLI do
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  def capture_stderr
    original_stderr = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original_stderr
  end

  it "prints plan JSON for a registered table" do
    PartitionGardener::Registry.register(
      PartitionGardener::Templates.sliding_window_monthly(
        table_name: "events",
        partition_key_column: "occurred_on",
        conflict_key: %w[id occurred_on]
      )
    )

    PartitionGardener.configure do |configuration|
      configuration.today_resolver = -> { Date.new(2026, 7, 5) }
    end

    allow(PartitionGardener::Connection).to receive_messages(attached_partitions: [], partition_attached?: false, partition_exists?: false, count_rows_in_partition_table: 0, count_rows_in_partition: 0)

    output = capture_stdout do
      described_class.start(%w[plan events])
    end

    payload = JSON.parse(output)
    expect(payload["schema_version"]).to eq("1.0")
    expect(payload["table_name"]).to eq("events")
    expect(payload["operations"]).to be_an(Array)
  end

  it "prints plan JSON for all composite branch tables" do
    PartitionGardener::Registry.register(
      PartitionGardener::Templates.composite_list_hash(
        parent_table: "repository_packages",
        discriminator_column: "branch",
        conflict_key: %w[id branch workspace_id],
        branches: [
          {
            name: "cached",
            value: "cached",
            where_condition: "branch = 'cached'",
            partition_key_column: "workspace_id",
            hash_modulus: 2
          },
          {
            name: "workspace",
            value: "workspace",
            where_condition: "branch = 'workspace'",
            partition_key_column: "workspace_id",
            hash_modulus: 2
          }
        ]
      )
    )

    PartitionGardener.configure do |configuration|
      configuration.today_resolver = -> { Date.new(2026, 7, 5) }
    end

    allow(PartitionGardener::Connection).to receive_messages(attached_partitions: [], partition_attached?: false, partition_exists?: false, count_rows_in_partition_table: 0, count_rows_in_partition: 0)

    output = capture_stdout do
      described_class.start(%w[plan repository_packages])
    end

    payload = JSON.parse(output)
    expect(payload["parent_table_name"]).to eq("repository_packages")
    expect(payload["tables"].map { |entry| entry["table_name"] }).to eq(
      %w[repository_packages repository_packages_cached repository_packages_workspace]
    )
  end

  it "requires --confirm for apply" do
    stderr = capture_stderr do
      expect {
        described_class.start(%w[apply events])
      }.to raise_error(SystemExit)
    end

    expect(stderr).to include("apply requires --confirm")
  end
end

require "spec_helper"

RSpec.describe PartitionGardener::DateRangeMaintenance do
  let(:executor) { instance_double(PartitionGardener::Executor) }
  let(:config) do
    PartitionGardener::Templates.sliding_window_monthly(
      table_name: "events",
      partition_key_column: "created_at",
      conflict_key: %w[created_at id]
    )
  end
  let(:maintenance) { described_class.new(config, executor: executor) }

  it "drains default rows and attaches under a parent write lock after CheckViolation" do
    identifier = Date.new(2024, 6, 1)
    partition_name = "events_2024_06"
    for_values_clause = "FROM ('2024-06-01') TO ('2024-07-01')"
    where_condition = "created_at >= '2024-06-01' AND created_at < '2024-07-01'"
    connection = instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)

    allow(PartitionGardener::Connection).to receive(:partition_exists?).with("events_default").and_return(true)
    allow(PartitionGardener::Connection).to receive(:count_rows_in_partition)
      .with("events_default", where_condition).and_return(5)
    allow(PartitionGardener::Connection).to receive(:quoted_table).with("events").and_return('"events"')
    allow(maintenance).to receive(:connection).and_return(connection)
    allow(connection).to receive_messages(transaction_open?: false)
    allow(connection).to receive(:transaction).and_yield
    allow(connection).to receive(:execute)
    allow(executor).to receive(:ensure_detached_partition_table!)
    allow(executor).to receive(:drain_rows_between_partitions!)

    attach_calls = 0
    violation = StandardError.new("PG::CheckViolation: updated partition constraint would be violated")
    allow(executor).to receive(:attach_partition) do |*|
      attach_calls += 1
      raise violation if attach_calls == 1
    end

    maintenance.send(
      :attach_archive_partition!,
      "events",
      partition_name,
      for_values_clause,
      where_condition
    )

    expect(connection).to have_received(:execute)
      .with("LOCK TABLE \"events\" IN SHARE ROW EXCLUSIVE MODE")
    expect(executor).to have_received(:ensure_detached_partition_table!).with(
      "events",
      partition_name,
      conflict_key: %w[created_at id]
    )
    expect(executor).to have_received(:drain_rows_between_partitions!).with(
      "events_default",
      partition_name,
      where_condition,
      %w[created_at id],
      cursor_columns: %w[created_at id]
    )
    expect(attach_calls).to eq(2)
  end

  it "skips archive attach when the bucket starts at or after the current lower bound" do
    identifier = Date.new(2026, 7, 1)
    allow(PartitionGardener.configuration).to receive(:today).and_return(Date.new(2026, 8, 13))
    allow(PartitionGardener::Connection).to receive(:current_partition_lower_bound)
      .with("events", "events_current")
      .and_return(Date.new(2026, 7, 1))
    allow(PartitionGardener::Connection).to receive_messages(
      partition_attached?: false,
      partition_exists?: false,
      count_rows_in_partition: 0
    )
    allow(executor).to receive(:create_partition)
    allow(executor).to receive(:attach_partition)
    allow(executor).to receive(:ensure_detached_partition_table!)
    allow(executor).to receive(:drain_rows_between_partitions!)
    allow(executor).to receive(:move_rows_to_parent_partition!)

    maintenance.send(:finalize_archive_from_source!, identifier, "events_current")

    expect(executor).not_to have_received(:create_partition)
    expect(executor).not_to have_received(:attach_partition)
    expect(executor).not_to have_received(:move_rows_to_parent_partition!)
  end
end

require "spec_helper"

RSpec.describe PartitionGardener::Executor do
  let(:connection) { double("connection") }
  let(:executor) { described_class.new(connection: connection, batch_size: 500) }

  before do
    allow(connection).to receive(:quote_table_name) { |name| %("#{name}") }
    allow(connection).to receive(:quote_column_name) { |name| %("#{name}") }
    allow(connection).to receive(:execute)
  end

  describe ".for_config" do
    it "uses per-table move_batch_size when configured" do
      config = {move_batch_size: 2_000}

      instance = described_class.for_config(config, connection: connection)

      expect(instance.instance_variable_get(:@batch_size)).to eq(2_000)
    end
  end

  describe "#ensure_parent_conflict_index!" do
    it "skips index creation when a unique index already covers the conflict key" do
      allow(PartitionGardener::Connection).to receive(:unique_index_covers?)
        .with("events", %w[id occurred_on])
        .and_return(true)

      executor.send(:ensure_parent_conflict_index!, "events", %w[id occurred_on])

      expect(connection).not_to have_received(:execute)
    end

    it "raises MissingConflictIndex when no unique index can be created" do
      allow(PartitionGardener::Connection).to receive(:unique_index_covers?)
        .with("events", %w[id occurred_on])
        .and_return(false, false)
      allow(connection).to receive(:execute).and_raise(StandardError.new("must include partition key"))

      expect {
        executor.send(:ensure_parent_conflict_index!, "events", %w[id occurred_on])
      }.to raise_error(
        PartitionGardener::MissingConflictIndex,
        /needs a unique index on \(id, occurred_on\) including the partition key/
      )
    end
  end

  describe "#execute_move_batch" do
    it "deletes only rows that inserted or already exist at the destination" do
      captured_sql = nil
      allow(connection).to receive(:execute) do |sql|
        captured_sql = sql
        [{"deleted" => 0, "batch_size" => 0, "last_cursor" => nil}]
      end

      executor.send(
        :execute_move_batch,
        source_partition_name: "events_default",
        insert_target: %("events"),
        where_condition: nil,
        conflict_key: %w[id occurred_on],
        cursor_columns: %w[id occurred_on],
        last_cursor: nil
      )

      expect(captured_sql).to include("RETURNING \"id\", \"occurred_on\"")
      expect(captured_sql).to include("duplicates_at_target AS")
      expect(captured_sql).to include("removable_rows AS")
      expect(captured_sql).to include("USING removable_rows")
      expect(captured_sql).not_to include("USING batch_rows")
    end
  end

  describe "#move_rows_with_keyset!" do
    it "raises UnmovedRowsRemaining when a full batch cannot be moved" do
      allow(executor).to receive(:execute_move_batch).and_return(
        {
          deleted: 0,
          batch_size: 500,
          last_cursor: {"id" => 1, "occurred_on" => "2024-01-01"}
        }
      )

      expect {
        executor.send(
          :move_rows_with_keyset!,
          source_partition_name: "events_default",
          insert_target: '"events"',
          where_condition: nil,
          conflict_key: %w[id occurred_on],
          cursor_columns: %w[id occurred_on]
        )
      }.to raise_error(
        PartitionGardener::UnmovedRowsRemaining,
        /events_default.*500 row\(s\)/
      )
    end

    it "finishes when the source partition is empty" do
      allow(executor).to receive(:execute_move_batch).and_return(
        {deleted: 0, batch_size: 0, last_cursor: nil}
      )
      allow(PartitionGardener.configuration).to receive(:current_run_metrics).and_return(nil)

      moved_rows = executor.send(
        :move_rows_with_keyset!,
        source_partition_name: "events_default",
        insert_target: '"events"',
        where_condition: nil,
        conflict_key: %w[id occurred_on],
        cursor_columns: %w[id occurred_on]
      )

      expect(moved_rows).to eq(0)
    end
  end
end

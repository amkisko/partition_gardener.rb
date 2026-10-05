require "spec_helper"

RSpec.describe PartitionGardener::SqlRunRecordStore do
  let(:connection) { double("connection") }
  let(:store) { described_class.new }

  before do
    PartitionGardener.configure do |configuration|
      configuration.connection_resolver = -> { connection }
    end
    allow(connection).to receive(:quote_table_name) { |name| %("#{name}") }
    allow(connection).to receive(:quote) { |value| "'#{value}'" }
    allow(connection).to receive(:execute).and_return([])
  end

  it "creates the checkpoint table on first save" do
    store.save(
      "events",
      {
        table_name: "events",
        phase: "detach",
        plan_signature: "abc123",
        staging_row_count: 4
      }
    )

    expect(connection).to have_received(:execute).with(/CREATE TABLE IF NOT EXISTS "partition_gardener_checkpoints"/)
    expect(connection).to have_received(:execute).with(/INSERT INTO "partition_gardener_checkpoints"/)
  end

  it "uses a configured checkpoint table name" do
    PartitionGardener.configure do |configuration|
      configuration.run_record_table_name = "custom_rebalance_checkpoints"
    end

    store.save(
      "events",
      {
        table_name: "events",
        phase: "detach",
        plan_signature: "abc123",
        staging_row_count: 4
      }
    )

    expect(connection).to have_received(:execute).with(/CREATE TABLE IF NOT EXISTS "custom_rebalance_checkpoints"/)
    expect(connection).to have_received(:execute).with(/INSERT INTO "custom_rebalance_checkpoints"/)
  end

  %w[partition_gardener_runs partition_gardener_run_records].each do |legacy_name|
    it "renames #{legacy_name} to the default checkpoint table" do
      allow(connection).to receive(:execute) do |sql|
        if sql.include?("pg_catalog.pg_class") && sql.include?("= '#{legacy_name}'")
          [{"present" => 1}]
        else
          []
        end
      end

      store.save(
        "events",
        {
          table_name: "events",
          phase: "detach",
          plan_signature: "abc123",
          staging_row_count: 4
        }
      )

      expect(connection).to have_received(:execute).with(
        %(ALTER TABLE "#{legacy_name}" RENAME TO "partition_gardener_checkpoints")
      )
    end
  end

  it "rejects a blank checkpoint table name" do
    PartitionGardener.configure do |configuration|
      configuration.run_record_table_name = " "
    end

    expect {
      store.save(
        "events",
        {
          table_name: "events",
          phase: "detach",
          plan_signature: "abc123",
          staging_row_count: 4
        }
      )
    }.to raise_error(ArgumentError, /run_record_table_name/)
  end

  it "does not rename a legacy table when a custom checkpoint name is configured" do
    PartitionGardener.configure do |configuration|
      configuration.run_record_table_name = "custom_rebalance_checkpoints"
    end

    store.save(
      "events",
      {
        table_name: "events",
        phase: "detach",
        plan_signature: "abc123",
        staging_row_count: 4
      }
    )

    expect(connection).not_to have_received(:execute).with(/ALTER TABLE .+ RENAME TO/)
  end

  it "loads persisted attributes" do
    allow(connection).to receive(:execute).and_return(
      [],
      [
        {
          "table_name" => "events",
          "phase" => "segments",
          "plan_signature" => "abc123",
          "staging_row_count" => "7"
        }
      ]
    )

    attributes = store.load("events")

    expect(attributes).to eq(
      table_name: "events",
      phase: "segments",
      plan_signature: "abc123",
      staging_row_count: 7
    )
  end

  it "creates schema only once when saves run concurrently" do
    create_calls = 0
    gate = Queue.new

    allow(connection).to receive(:execute) do |sql|
      if sql.include?("CREATE TABLE IF NOT EXISTS")
        create_calls += 1
        gate.pop
      end
      []
    end

    threads = Array.new(4) do
      Thread.new do
        gate << true
        store.save(
          "events",
          {
            table_name: "events",
            phase: "detach",
            plan_signature: "abc123",
            staging_row_count: 1
          }
        )
      end
    end
    threads.each(&:join)

    expect(create_calls).to eq(1)
  end
end

RSpec.describe PartitionGardener::ActiveRecordRunRecordStore do
  it "is an alias for SqlRunRecordStore" do
    expect(described_class).to eq(PartitionGardener::SqlRunRecordStore)
  end
end

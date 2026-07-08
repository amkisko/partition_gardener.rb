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

  it "creates the run record table on first save" do
    store.save(
      "events",
      {
        table_name: "events",
        phase: "detach",
        plan_signature: "abc123",
        staging_row_count: 4
      }
    )

    expect(connection).to have_received(:execute).with(/CREATE TABLE IF NOT EXISTS "partition_gardener_run_records"/)
    expect(connection).to have_received(:execute).with(/INSERT INTO "partition_gardener_run_records"/)
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

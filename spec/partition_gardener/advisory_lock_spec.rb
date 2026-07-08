require "spec_helper"

RSpec.describe PartitionGardener::AdvisoryLock do
  let(:connection) { double("connection") }

  before do
    allow(PartitionGardener::Connection).to receive(:connection).and_return(connection)
    allow(connection).to receive(:quote) { |value| "'#{value}'" }
    allow(connection).to receive(:execute)
  end

  it "acquires and releases session advisory lock without blocking" do
    PartitionGardener.configuration.advisory_lock_mode = :session
    allow(connection).to receive(:execute).with(/pg_try_advisory_lock/).and_return([double(values: [true])])
    described_class.with_table_lock("events") { :done }

    expect(connection).to have_received(:execute).with(
      "SELECT pg_try_advisory_lock(hashtext('partition_gardener'), hashtext('events'))"
    )
    expect(connection).to have_received(:execute).with(
      "SELECT pg_advisory_unlock(hashtext('partition_gardener'), hashtext('events'))"
    )
  end

  it "raises LockNotAcquired when session lock is held" do
    PartitionGardener.configuration.advisory_lock_mode = :session
    allow(connection).to receive(:execute).with(/pg_try_advisory_lock/).and_return([double(values: [false])])

    expect {
      described_class.with_table_lock("events") { :done }
    }.to raise_error(PartitionGardener::LockNotAcquired, /session advisory lock not acquired/)
  end

  it "uses transaction advisory lock by default" do
    allow(connection).to receive(:transaction).and_yield
    allow(connection).to receive(:execute).with(/pg_try_advisory_xact_lock/).and_return([double(values: [true])])

    described_class.with_table_lock("events") { :done }

    expect(connection).to have_received(:transaction)
  end

  it "uses transaction advisory lock when configured" do
    PartitionGardener.configuration.advisory_lock_mode = :transaction
    allow(connection).to receive(:transaction).and_yield
    allow(connection).to receive(:execute).with(/pg_try_advisory_xact_lock/).and_return([double(values: [true])])

    described_class.with_table_lock("events") { :done }

    expect(connection).to have_received(:transaction)
    expect(connection).to have_received(:execute).with(
      "SELECT pg_try_advisory_xact_lock(hashtext('partition_gardener'), hashtext('events'))"
    )
  end

  it "raises LockNotAcquired when transaction lock is held" do
    PartitionGardener.configuration.advisory_lock_mode = :transaction
    allow(connection).to receive(:transaction).and_yield
    allow(connection).to receive(:execute).with(/pg_try_advisory_xact_lock/).and_return([double(values: [false])])

    expect {
      described_class.with_table_lock("events") { :done }
    }.to raise_error(PartitionGardener::LockNotAcquired, /transaction advisory lock not acquired/)
  end
end

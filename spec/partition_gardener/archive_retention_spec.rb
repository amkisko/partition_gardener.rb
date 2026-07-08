require "spec_helper"

RSpec.describe PartitionGardener::ArchiveRetention do
  let(:today) { Date.new(2026, 7, 5) }
  let(:executor) { instance_double(PartitionGardener::Executor) }
  let(:config) do
    PartitionGardener::Templates.sliding_window_monthly(
      table_name: "events",
      partition_key_column: "created_at",
      conflict_key: %w[created_at id],
      retention_months: 12
    )
  end

  before do
    PartitionGardener.configure do |configuration|
      configuration.today_resolver = -> { today }
    end
    allow(executor).to receive(:detach_partition)
    allow(executor).to receive(:drop_table)
  end

  it "does nothing when retention_months is not set" do
    bare_config = config.merge(retention_months: nil)
    expect(
      described_class.new(bare_config, executor: executor).apply!
    ).to eq(0)
  end

  it "previews archive retention by default when retention_months is set" do
    old_partition = double(
      default: false,
      name: "events_2024_06",
      range_start: Date.new(2024, 6, 1),
      range_end: Date.new(2024, 7, 1)
    )

    allow(PartitionGardener::Connection).to receive(:attached_partitions).with("events").and_return([old_partition])
    notifications = []
    PartitionGardener.configure do |configuration|
      configuration.today_resolver = -> { today }
      configuration.notifier = ->(message, context: {}) { notifications << [message, context] }
    end

    dropped = described_class.new(config, executor: executor).apply!

    expect(dropped).to eq(1)
    expect(executor).not_to have_received(:detach_partition)
    expect(notifications.first.first).to include("Would drop archive partition")
  end

  it "drops archive partitions older than retention window" do
    drop_config = config.merge(retention_apply: true)
    old_partition = double(
      default: false,
      name: "events_2024_06",
      range_start: Date.new(2024, 6, 1),
      range_end: Date.new(2024, 7, 1)
    )
    current_partition = double(
      default: false,
      name: "events_current",
      range_start: Date.new(2026, 7, 1),
      range_end: Date.new(2027, 7, 1)
    )

    allow(PartitionGardener::Connection).to receive(:attached_partitions).with("events").and_return(
      [old_partition, current_partition]
    )

    dropped = described_class.new(drop_config, executor: executor).apply!

    expect(dropped).to eq(1)
    expect(executor).to have_received(:detach_partition).with("events", "events_2024_06", concurrently: false)
    expect(executor).to have_received(:drop_table).with("events_2024_06")
  end

  it "detaches but keeps table when retention_keep_table is true" do
    keep_config = config.merge(retention_keep_table: true, retention_apply: true)
    old_partition = double(
      default: false,
      name: "events_2024_06",
      range_start: Date.new(2024, 6, 1),
      range_end: Date.new(2024, 7, 1)
    )

    allow(PartitionGardener::Connection).to receive(:attached_partitions).with("events").and_return([old_partition])

    described_class.new(keep_config, executor: executor).apply!

    expect(executor).to have_received(:detach_partition).with("events", "events_2024_06", concurrently: false)
    expect(executor).not_to have_received(:drop_table)
  end
end

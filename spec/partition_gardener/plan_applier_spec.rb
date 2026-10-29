require "spec_helper"

RSpec.describe PartitionGardener::PlanApplier do
  let(:config) do
    PartitionGardener::Templates.sliding_window_monthly(
      table_name: "events",
      partition_key_column: "occurred_on",
      conflict_key: %w[id occurred_on]
    )
  end
  let(:executor) { instance_double(PartitionGardener::Executor) }
  let(:applier) { described_class.new(config, executor: executor) }
  let(:plan) do
    PartitionGardener::Plan::Result.new(
      segments: [
        PartitionGardener::Plan::Segment.new(
          name: "events_current",
          range_start: Date.new(2026, 7, 1),
          range_end: Date.new(2027, 7, 1),
          kind: :filler
        ),
        PartitionGardener::Plan::Segment.new(
          name: "events_future",
          range_start: Date.new(2027, 7, 1),
          range_end: :max,
          kind: :future
        )
      ],
      hot_buckets: []
    )
  end

  before do
    PartitionGardener.configure do |configuration|
      configuration.run_record_store = PartitionGardener::MemoryRunRecordStore.new
      configuration.run_record_enabled = true
    end

    allow(PartitionGardener::DefaultPartition).to receive(:ensure!)
    connection = double("connection")
    allow(connection).to receive(:execute).and_return([])
    allow(connection).to receive(:quote) { |value| "'#{value}'" }
    allow(connection).to receive(:quote_table_name) { |name| %("#{name}") }
    allow(PartitionGardener::Connection).to receive_messages(partition_exists?: false, partition_attached?: false, count_rows_in_partition_table: 0, connection: connection)
    allow(executor).to receive(:drop_table)
    allow(executor).to receive(:ensure_detached_partition_table!)
    allow(executor).to receive(:detach_partition)
    allow(executor).to receive(:move_all_rows_between_partitions!)
    allow(executor).to receive(:create_partition)
    allow(executor).to receive(:move_all_rows_to_parent!)
    allow(PartitionGardener::RunRecord).to receive(:clear)
  end

  it "raises when staging holds rows without a resumable run record" do
    attached = [
      PartitionGardener::Plan::Segment.new(
        name: "events_current",
        range_start: Date.new(2026, 7, 1),
        range_end: Date.new(2026, 9, 1),
        kind: :filler
      )
    ]
    allow(PartitionGardener::Planner).to receive(:new).and_return(
      instance_double(PartitionGardener::Planner, attached_tail_segments: attached)
    )
    allow(PartitionGardener::Connection).to receive(:partition_exists?)
      .with("events_rebalance_staging")
      .and_return(true)
    allow(PartitionGardener::Connection).to receive(:count_rows_in_partition_table)
      .with("events_rebalance_staging")
      .and_return(12)
    allow(PartitionGardener::RunRecord).to receive(:load).with("events").and_return(nil)

    expect {
      applier.apply!(plan)
    }.to raise_error(
      PartitionGardener::OrphanedRebalanceStaging,
      /events_rebalance_staging holds 12 row\(s\)/
    )
  end

  it "resumes detach work when the run record is still at phase detach" do
    signature = "sig"
    record = PartitionGardener::RunRecord.start(table_name: "events", plan_signature: signature)
    expect(record.phase).to eq("detach")

    attached_names = ["events_current"]
    allow(PartitionGardener::Connection).to receive(:partition_exists?) do |name|
      name == "events_rebalance_staging" || attached_names.include?(name)
    end
    allow(PartitionGardener::Connection).to receive(:partition_attached?) do |_table, name|
      attached_names.include?(name)
    end
    allow(PartitionGardener::Connection).to receive(:count_rows_in_partition_table).and_return(0)
    allow(applier).to receive_messages(managed_tail_partition_names: ["events_current"], strategy: instance_double(
      PartitionGardener::Strategy::DateRange,
      rebalance_default_drain_where_condition: "FALSE",
      cursor_columns: %w[occurred_on id],
      segment_for_values_clause: "FROM ('2026-07-01') TO ('2027-07-01')"
    ))
    allow(executor).to receive(:detach_partition) do |_table, name|
      attached_names.delete(name)
    end
    allow(executor).to receive(:create_partition) do |_table, name, _clause|
      attached_names << name
    end
    allow(executor).to receive(:drop_table) do |name|
      attached_names.delete(name)
    end
    operations = [
      PartitionGardener::PlanDiff::Operation.new(
        :reshape,
        plan.segments.first,
        PartitionGardener::Plan::Segment.new(
          name: "events_current",
          range_start: Date.new(2026, 7, 1),
          range_end: Date.new(2026, 9, 1),
          kind: :filler
        )
      )
    ]

    applier.send(:apply_resuming!, plan, operations, "events_rebalance_staging", record)

    expect(executor).to have_received(:detach_partition).with("events", "events_current")
    expect(executor).to have_received(:create_partition).at_least(:once)
  end

  it "refuses to create a segment when a detached table already owns the name" do
    allow(PartitionGardener::Connection).to receive(:partition_attached?).and_return(false)
    allow(PartitionGardener::Connection).to receive(:partition_exists?).with("events_current").and_return(true)

    expect {
      applier.send(:create_segments!, plan.segments.take(1))
    }.to raise_error(StandardError, /exists but is not attached/)
  end

  it "skips segment creation in hybrid mode" do
    hybrid_config = config.merge(maintenance_backend: :hybrid_layout_only)
    hybrid_applier = described_class.new(hybrid_config, executor: executor)

    attached = [
      PartitionGardener::Plan::Segment.new(
        name: "events_current",
        range_start: Date.new(2026, 7, 1),
        range_end: Date.new(2026, 9, 1),
        kind: :filler
      )
    ]
    allow(PartitionGardener::Planner).to receive(:new).and_return(
      instance_double(PartitionGardener::Planner, attached_tail_segments: attached)
    )
    allow(PartitionGardener::Connection).to receive(:partition_exists?)
      .with("events_rebalance_staging")
      .and_return(false)
    allow(PartitionGardener::RunRecord).to receive(:load).with("events").and_return(nil)

    hybrid_applier.apply!(plan)

    expect(executor).not_to have_received(:create_partition)
  end
end

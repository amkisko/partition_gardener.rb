require "spec_helper"
require_relative "support/database"
require_relative "support/fixtures"

RSpec.describe "rebalance resume", :integration do
  include PartitionGardener::Integration::Fixtures

  let(:today) { Date.new(2026, 7, 5) }
  let(:table_name) { unique_table_name }

  before do
    PartitionGardener::Integration::Database.configure_gardener!(today: today)
    create_sliding_window_table!(table_name, today: today)
    register_sliding_window!(table_name, today: today, split_row_threshold: 2)
  end

  after do
    PartitionGardener::RunRecord.clear(table_name)
    drop_table_cascade!(table_name)
  end

  it "resumes from a detach-phase run record and finishes rebalance" do
    hot_month = (today + 2.months).beginning_of_month
    hot_partition = month_partition_name(table_name, hot_month)

    insert_row!(table_name, id: 1, occurred_on: hot_month)
    insert_row!(table_name, id: 2, occurred_on: hot_month + 1)

    config = PartitionGardener::Registry.find_by_table_name(table_name)
    plan = PartitionGardener::Planner.new(config).build
    plan_signature = PartitionGardener::PlanDiff.plan_signature(plan.segments)
    staging_name = PartitionGardener::Naming.rebalance_staging_partition_name(table_name)

    applier = PartitionGardener::PlanApplier.new(config, job_class_name: "Integration")
    applier.send(:prepare_staging!, staging_name)
    applier.send(:detach_managed_tail_partitions!, staging_name, skip_names: [])
    PartitionGardener::RunRecord.start(table_name: table_name, plan_signature: plan_signature)
      .advance!("detach", staging_row_count: PartitionGardener::Connection.count_rows_in_partition_table(staging_name))

    expect(PartitionGardener::Connection.partition_exists?(staging_name)).to be(true)
    expect(PartitionGardener::RunRecord.load(table_name).phase).to eq("detach")

    applier.apply!(plan)

    expect(PartitionGardener::RunRecord.load(table_name)).to be_nil
    expect(PartitionGardener::Connection.partition_exists?(staging_name)).to be(false)
    expect(partition_attached?(table_name, hot_partition)).to be(true)
    expect(PartitionGardener::GapDetection.call(table_name)).to be_empty
  end
end

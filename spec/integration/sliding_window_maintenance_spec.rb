require "spec_helper"
require_relative "support/database"
require_relative "support/fixtures"

RSpec.describe "sliding window maintenance", :integration do
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

  def run_maintenance!
    config = PartitionGardener::Registry.find_by_table_name(table_name)
    PartitionGardener.maintenance_for(config, job_class_name: "Integration").run!
  end

  it "drains archive rows from default into a monthly child" do
    archive_date = Date.new(2024, 6, 15)
    archive_partition = month_partition_name(table_name, archive_date.beginning_of_month)

    insert_row!(default_name(table_name), id: 1, occurred_on: archive_date)

    expect(partition_attached?(table_name, archive_partition)).to be(false)
    expect(count_rows(default_name(table_name))).to eq(1)

    run_maintenance!

    expect(partition_attached?(table_name, archive_partition)).to be(true)
    expect(count_rows(default_name(table_name), where: "occurred_on = '#{archive_date}'")).to eq(0)
    expect(count_rows(archive_partition)).to eq(1)
  end

  it "splits a hot future month out of current when row count reaches threshold" do
    hot_month = (today + 2.months).beginning_of_month
    hot_partition = month_partition_name(table_name, hot_month)

    insert_row!(table_name, id: 1, occurred_on: hot_month)
    insert_row!(table_name, id: 2, occurred_on: hot_month + 1)

    expect(partition_attached?(table_name, hot_partition)).to be(false)

    run_maintenance!

    expect(partition_attached?(table_name, hot_partition)).to be(true)
    expect(count_rows(hot_partition)).to eq(2)
    expect(count_rows(current_name(table_name), where: "occurred_on >= '#{hot_month}' AND occurred_on < '#{hot_month.next_month}'")).to eq(0)
  end

  it "leaves tail layout without partition gaps" do
    run_maintenance!

    gaps = PartitionGardener::GapDetection.call(table_name)
    expect(gaps).to be_empty
  end
end

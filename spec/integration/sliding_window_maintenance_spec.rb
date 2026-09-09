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

  context "when today rolls from July into August" do
    let(:today) { Date.new(2026, 7, 15) }

    it "attaches the July archive and a current partition from August" do
      insert_row!(table_name, id: 1, occurred_on: Date.new(2026, 7, 10))

      run_maintenance!

      PartitionGardener::Integration::Database.configure_gardener!(today: Date.new(2026, 8, 13))
      run_maintenance!

      july_partition = month_partition_name(table_name, Date.new(2026, 7, 1))
      expect(partition_attached?(table_name, july_partition)).to be(true)
      expect(count_rows(july_partition)).to eq(1)
      expect(count_rows(default_name(table_name))).to eq(0)
      expect(
        PartitionGardener::Connection.current_partition_lower_bound(table_name, current_name(table_name))
      ).to eq(Date.new(2026, 8, 1))
    end
  end

  context "when monthly children already occupy the window start" do
    let(:today) { Date.new(2026, 9, 9) }
    let(:september_partition) { "#{table_name}_2026_09_01" }
    let(:horizon_partition) { "#{table_name}_2027_09_01" }

    before do
      drop_table_cascade!(table_name)
      PartitionGardener::Registry.reset!
      create_monthly_catalog_through!(table_name, from: Date.new(2026, 6, 1), through: Date.new(2026, 9, 1))
      attach_monthly_child!(table_name, Date.new(2027, 9, 1))
      register_sliding_window!(table_name, today: today, split_row_threshold: 100_000)
      insert_row!(september_partition, id: 1, occurred_on: Date.new(2026, 9, 4))
    end

    it "attaches open after the last occupying month and keeps that month attached" do
      run_maintenance!

      expect(partition_attached?(table_name, september_partition)).to be(true)
      expect(count_rows(september_partition)).to eq(1)
      expect(partition_attached?(table_name, current_name(table_name))).to be(false)
      expect(partition_attached?(table_name, open_name(table_name))).to be(true)
      expect(partition_attached?(table_name, horizon_partition)).to be(true)
      expect(partition_attached?(table_name, future_name(table_name))).to be(true)
      expect(
        PartitionGardener::Connection.current_partition_lower_bound(table_name, open_name(table_name))
      ).to eq(Date.new(2026, 10, 1))
      expect(
        PartitionGardener::Connection.current_partition_lower_bound(table_name, future_name(table_name))
      ).to eq(Date.new(2027, 10, 1))

      PartitionGardener::Connection.clear_attached_partitions_cache!
      expect(PartitionGardener::GapDetection.call(table_name)).to be_empty
    end
  end

  def create_monthly_catalog_through!(table_name, from:, through:)
    connection = PartitionGardener::Integration::Database.connection
    quoted_parent = quote_table(table_name)

    connection.execute(<<~SQL)
      CREATE TABLE #{quoted_parent} (
        id bigint NOT NULL,
        occurred_on date NOT NULL,
        PRIMARY KEY (id, occurred_on)
      ) PARTITION BY RANGE (occurred_on)
    SQL

    connection.execute(<<~SQL)
      CREATE TABLE #{quote_table(default_name(table_name))} PARTITION OF #{quoted_parent} DEFAULT
    SQL

    month = from.beginning_of_month
    last_month = through.beginning_of_month
    while month <= last_month
      attach_monthly_child!(table_name, month)
      month = month.next_month
    end
  end

  def attach_monthly_child!(table_name, month)
    month = month.beginning_of_month
    next_month = month.next_month
    child_name = "#{table_name}_#{month.strftime("%Y_%m_%d")}"
    connection = PartitionGardener::Integration::Database.connection
    connection.execute(<<~SQL)
      CREATE TABLE #{quote_table(child_name)} PARTITION OF #{quote_table(table_name)}
      FOR VALUES FROM ('#{month}') TO ('#{next_month}')
    SQL
  end
end

require "spec_helper"
require_relative "support/database"
require_relative "support/fixtures"

RSpec.describe "hot switch migration", :integration do
  include PartitionGardener::Integration::Fixtures

  let(:today) { Date.new(2026, 7, 5) }
  let(:live_table) { unique_table_name("pg_live") }
  let(:partitioned_table) { unique_table_name("pg_part") }

  let(:migration) do
    partition_config = {
      partition_name_format: ->(identifier) { "#{live_table}_#{identifier.strftime("%Y_%m")}" },
      partition_definition: ->(date) do
        start_range = date.beginning_of_month
        end_range = date.next_month.beginning_of_month
        "FROM ('#{start_range}') TO ('#{end_range}')"
      end,
      partitions_to_create: lambda { |run_today|
        [run_today.beginning_of_month]
      }
    }

    Class.new do
      include PartitionGardener::Migration::HotSwitchConcern

      define_method(:initialize) do |config|
        @config = config
      end

      define_method(:hot_switch_config) { @config }

      def execute(sql)
        PartitionGardener::Integration::Database.connection.execute(sql)
      end

      def connection
        PartitionGardener::Integration::Database.connection
      end

      def say(_message)
      end

      def transaction
        connection.transaction { yield }
      end
    end.new(
      current_table: live_table,
      partitioned_table: partitioned_table,
      partition_key_column: "occurred_on",
      conflict_key: %w[id occurred_on],
      partition_config: partition_config
    )
  end

  before do
    PartitionGardener::Integration::Database.configure_gardener!(today: today)
    create_hot_switch_source_table!(live_table)
    create_hot_switch_partitioned_table!(partitioned_table, today: today)
  end

  after do
    drop_table_cascade!(live_table)
    drop_table_cascade!(partitioned_table)
  end

  it "premakes future month partitions on the shadow table" do
    migration.ensure_future_partitions_exist(months_ahead: 1)

    next_month = today.next_month.beginning_of_month
    partition_name = "#{partitioned_table}_#{next_month.strftime("%Y_%m")}"

    expect(PartitionGardener::Connection.partition_exists?(partition_name)).to be(true)
  end

  it "syncs delta rows from the live table into the partitioned table" do
    insert_row!(live_table, id: 1, occurred_on: today)
    insert_row!(live_table, id: 2, occurred_on: today + 1)

    migration.sync_delta_data

    expect(count_rows(partitioned_table)).to eq(2)
    expect(count_rows(partitioned_table, where: "id = 1")).to eq(1)
  end

  it "syncs delta rows in batches when batch size is limited" do
    3.times do |index|
      insert_row!(live_table, id: index + 1, occurred_on: today + index)
    end

    migration.sync_delta_data(batch_size: 1)

    expect(count_rows(partitioned_table)).to eq(3)
  end

  it "renames shadow partitions during hot switch" do
    migration.ensure_future_partitions_exist(months_ahead: 0)
    insert_row!(partitioned_table, id: 1, occurred_on: today)

    migration.hot_switch_tables

    expect(PartitionGardener::Connection.partition_exists?(live_table)).to be(true)
    expect(PartitionGardener::Connection.partition_exists?(partitioned_table)).to be(false)
    expect(count_rows(live_table)).to eq(1)
    expect(PartitionGardener::Connection.partition_exists?(default_name(live_table))).to be(true)
  end

  it "repoints serial sequences to the live table after hot switch" do
    drop_table_cascade!(live_table)
    create_hot_switch_source_table_with_serial!(live_table)

    migration.ensure_future_partitions_exist(months_ahead: 0)
    migration.hot_switch_tables

    expect(serial_sequence_owned_by_table?(live_table, "id")).to be(true)
  end

  it "analyzes shadow partitions before switch" do
    migration.ensure_future_partitions_exist(months_ahead: 0)

    expect { migration.analyze_shadow_partitions! }.not_to raise_error
  end

  it "round-trips hot switch and unswitch" do
    migration.ensure_future_partitions_exist(months_ahead: 0)
    insert_row!(partitioned_table, id: 1, occurred_on: today)

    migration.hot_switch_tables
    migration.hot_unswitch_tables

    expect(PartitionGardener::Connection.partition_exists?(partitioned_table)).to be(true)
    expect(PartitionGardener::Connection.partition_exists?("#{live_table}_old")).to be(false)
    expect(count_rows(live_table)).to eq(0)
    expect(count_rows(partitioned_table)).to eq(1)
  end

  it "syncs straggler rows from the retired table after swap" do
    migration.ensure_future_partitions_exist(months_ahead: 0)
    migration.hot_switch_tables

    retired_table = "#{live_table}_old"
    insert_row!(retired_table, id: 99, occurred_on: today)

    migration.sync_delta_data(swapped: true)

    expect(count_rows(live_table, where: "id = 99")).to eq(1)
  end
end

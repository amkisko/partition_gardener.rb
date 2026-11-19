require "spec_helper"
require_relative "support/database"
require_relative "support/fixtures"

RSpec.describe "premake monthly maintenance", :integration do
  include PartitionGardener::Integration::Fixtures

  let(:today) { Date.new(2026, 7, 5) }
  let(:table_name) { unique_table_name }

  before do
    PartitionGardener::Integration::Database.configure_gardener!(today: today)
    connection = PartitionGardener::Integration::Database.connection

    connection.execute(<<~SQL)
      CREATE TABLE #{quote_table(table_name)} (
        id bigint NOT NULL,
        occurred_on date NOT NULL,
        PRIMARY KEY (id, occurred_on)
      ) PARTITION BY RANGE (occurred_on)
    SQL

    connection.execute(<<~SQL)
      CREATE TABLE #{quote_table(default_name(table_name))} PARTITION OF #{quote_table(table_name)} DEFAULT
    SQL

    PartitionGardener::Registry.register(
      PartitionGardener::Templates.premake_monthly(
        table_name: table_name,
        partition_key_column: "occurred_on",
        conflict_key: %w[id occurred_on],
        premake_months: 2
      )
    )
  end

  after do
    drop_table_cascade!(table_name)
  end

  it "creates monthly partitions through the premake horizon" do
    config = PartitionGardener::Registry.find_by_table_name(table_name)
    PartitionGardener::PremakeMonthlyMaintenance.new(config).run!

    (0..2).each do |offset|
      month = today.beginning_of_month + offset.months
      partition_name = month_partition_name(table_name, month)
      expect(partition_attached?(table_name, partition_name)).to be(true)
    end
  end

  it "moves overlapping default rows into the new month child before attach" do
    insert_row!(table_name, id: 1, occurred_on: Date.new(2026, 7, 15))
    insert_row!(table_name, id: 2, occurred_on: Date.new(2026, 8, 2))

    expect(count_rows(default_name(table_name))).to eq(2)

    config = PartitionGardener::Registry.find_by_table_name(table_name)
    expect {
      PartitionGardener::PremakeMonthlyMaintenance.new(config).run!
    }.not_to raise_error

    july = month_partition_name(table_name, Date.new(2026, 7, 1))
    august = month_partition_name(table_name, Date.new(2026, 8, 1))
    september = month_partition_name(table_name, Date.new(2026, 9, 1))

    expect(partition_attached?(table_name, july)).to be(true)
    expect(partition_attached?(table_name, august)).to be(true)
    expect(partition_attached?(table_name, september)).to be(true)
    expect(count_rows(july)).to eq(1)
    expect(count_rows(august)).to eq(1)
    expect(count_rows(default_name(table_name))).to eq(0)
    expect(count_rows(table_name, where: "id = 1")).to eq(1)
    expect(count_rows(table_name, where: "id = 2")).to eq(1)
  end

  it "survives a second maintenance pass after default rows were already drained" do
    insert_row!(table_name, id: 11, occurred_on: Date.new(2026, 7, 20))
    config = PartitionGardener::Registry.find_by_table_name(table_name)

    PartitionGardener::PremakeMonthlyMaintenance.new(config).run!
    expect {
      PartitionGardener::PremakeMonthlyMaintenance.new(config).run!
    }.not_to raise_error

    july = month_partition_name(table_name, Date.new(2026, 7, 1))
    expect(partition_attached?(table_name, july)).to be(true)
    expect(count_rows(july)).to eq(1)
    expect(count_rows(default_name(table_name))).to eq(0)
  end
end

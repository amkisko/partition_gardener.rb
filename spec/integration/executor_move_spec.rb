require "spec_helper"
require_relative "support/database"
require_relative "support/fixtures"

RSpec.describe "executor row moves", :integration do
  include PartitionGardener::Integration::Fixtures

  let(:connection) { PartitionGardener::Integration::Database.connection }
  let(:executor) { PartitionGardener::Executor.new(connection: connection, batch_size: 100) }
  let(:source_table) { unique_table_name("move_source") }
  let(:destination_table) { unique_table_name("move_dest") }
  let(:conflict_key) { %w[id occurred_on] }

  before do
    PartitionGardener::Integration::Database.configure_gardener!
    connection.execute(<<~SQL)
      CREATE TABLE #{quote_table(source_table)} (
        id bigint NOT NULL,
        occurred_on date NOT NULL,
        PRIMARY KEY (id, occurred_on)
      )
    SQL
    connection.execute(<<~SQL)
      CREATE TABLE #{quote_table(destination_table)} (
        LIKE #{quote_table(source_table)} INCLUDING ALL
      )
    SQL
  end

  after do
    drop_table_cascade!(source_table)
    drop_table_cascade!(destination_table)
  end

  it "moves rows that exist only in the source partition" do
    insert_row!(source_table, id: 1, occurred_on: Date.new(2024, 6, 15))

    moved_rows = executor.move_all_rows_between_partitions!(
      source_table,
      destination_table,
      conflict_key
    )

    expect(moved_rows).to eq(1)
    expect(count_rows(source_table)).to eq(0)
    expect(count_rows(destination_table)).to eq(1)
  end

  it "clears duplicate rows from the source when the destination already holds the conflict key" do
    occurred_on = Date.new(2024, 6, 15)
    insert_row!(source_table, id: 1, occurred_on: occurred_on)
    insert_row!(destination_table, id: 1, occurred_on: occurred_on)

    moved_rows = executor.move_all_rows_between_partitions!(
      source_table,
      destination_table,
      conflict_key
    )

    expect(moved_rows).to eq(1)
    expect(count_rows(source_table)).to eq(0)
    expect(count_rows(destination_table)).to eq(1)
  end
end

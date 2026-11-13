require "spec_helper"
require_relative "support/database"

RSpec.describe "partman probe inside an open transaction", :integration do
  before do
    PartitionGardener::Integration::Database.configure_gardener!
  end

  it "does not abort the outer transaction when partman.part_config is absent" do
    connection = PartitionGardener::Integration::Database.connection
    expect(connection.select_value("SELECT to_regclass('partman.part_config')::text")).to be_nil

    connection.transaction do
      expect(PartitionGardener::MaintenanceBackend.partman_parent_configured?("events")).to be(false)

      expect {
        connection.execute("SELECT 1")
      }.not_to raise_error

      raise ActiveRecord::Rollback
    end
  end

  it "keeps Registry.register from aborting the outer transaction when partman is absent" do
    connection = PartitionGardener::Integration::Database.connection
    expect(connection.select_value("SELECT to_regclass('partman.part_config')::text")).to be_nil

    connection.transaction do
      expect {
        PartitionGardener::Registry.register(
          PartitionGardener::Templates.sliding_window_monthly(
            table_name: "events",
            partition_key_column: "occurred_on",
            conflict_key: %w[id occurred_on]
          )
        )
      }.not_to raise_error

      expect {
        connection.execute("SELECT 1")
      }.not_to raise_error

      raise ActiveRecord::Rollback
    end
  end

  it "returns true when partman.part_config lists the parent" do
    connection = PartitionGardener::Integration::Database.connection

    connection.execute("CREATE SCHEMA IF NOT EXISTS partman")
    connection.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS partman.part_config (
        parent_table text PRIMARY KEY
      )
    SQL
    connection.execute(<<~SQL)
      INSERT INTO partman.part_config (parent_table)
      VALUES ('public.events')
      ON CONFLICT DO NOTHING
    SQL

    begin
      expect(PartitionGardener::Connection.partman_parent_configured?("events")).to be(true)
      expect(PartitionGardener::Connection.partman_parent_configured?("other")).to be(false)
    ensure
      connection.execute("DROP SCHEMA partman CASCADE")
    end
  end
end

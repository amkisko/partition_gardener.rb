require "spec_helper"
require_relative "support/database"
require_relative "support/fixtures"

RSpec.describe "pg connection maintenance", :integration do
  include PartitionGardener::Integration::Fixtures

  let(:today) { Date.new(2026, 7, 5) }
  let(:table_name) { unique_table_name("pg_pgconn") }

  before do
    PartitionGardener::Integration::Database.configure_pg_connection!(today: today)
    create_sliding_window_table!(table_name, today: today)
    register_sliding_window!(table_name, today: today, split_row_threshold: 2)
  end

  after do
    PartitionGardener::RunRecord.clear(table_name)
    drop_table_cascade!(table_name)
  end

  it "runs maintenance through PgConnection with transaction advisory locks" do
    PartitionGardener.configuration.advisory_lock_mode = :transaction
    insert_row!(table_name, id: 1, occurred_on: Date.new(2024, 6, 15))

    expect {
      PartitionGardener.run!(table_name: table_name, job_class_name: "Integration")
    }.not_to raise_error

    archive_partition = month_partition_name(table_name, Date.new(2024, 6, 1))
    expect(partition_attached?(table_name, archive_partition)).to be(true)
  end

  it "defaults standalone connections to session advisory locks" do
    expect(PartitionGardener.configuration.advisory_lock_mode).to eq(:session)
  end
end

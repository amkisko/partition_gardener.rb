require "spec_helper"
require_relative "support/database"
require_relative "support/fixtures"

RSpec.describe "hash branches maintenance", :integration do
  include PartitionGardener::Integration::Fixtures

  let(:table_name) { unique_table_name("pg_hash") }
  let(:archive_partition) { hash_archive_partition_name(table_name, 2) }
  let(:hot_partition) { hash_hot_partition_name(table_name, 2) }

  before do
    PartitionGardener::Integration::Database.configure_gardener!
    create_hash_branches_table!(table_name, hash_modulus: 4)
    register_hash_branches!(table_name, hash_modulus: 4, split_row_threshold: 2)
  end

  after do
    PartitionGardener::RunRecord.clear(table_name)
    drop_table_cascade!(table_name)
  end

  def run_maintenance!
    config = PartitionGardener::Registry.find_by_table_name(table_name)
    PartitionGardener.maintenance_for(config, job_class_name: "Integration").run!
  end

  it "promotes a hot hash remainder into the current zone" do
    insert_hash_row!(archive_partition, id: 1, workspace_id: 2)
    insert_hash_row!(archive_partition, id: 2, workspace_id: 2)

    expect(partition_attached?(table_name, hot_partition)).to be(false)

    run_maintenance!

    expect(partition_attached?(table_name, hot_partition)).to be(true)
    expect(count_rows(hot_partition)).to eq(2)
  end
end

require "spec_helper"
require_relative "support/database"
require_relative "support/fixtures"

RSpec.describe "composite maintenance", :integration do
  include PartitionGardener::Integration::Fixtures

  let(:today) { Date.new(2026, 7, 5) }
  let(:parent_name) { unique_table_name("pg_composite") }
  let(:cached_name) { "#{parent_name}_cached" }
  let(:workspace_name) { "#{parent_name}_workspace" }

  before do
    PartitionGardener::Integration::Database.configure_gardener!(today: today)
    create_composite_list_hash_tables!(parent_name, hash_modulus: 2)
    register_composite_list_hash!(parent_name, hash_modulus: 2)
  end

  after do
    drop_table_cascade!(parent_name)
  end

  def run_composite_maintenance!
    config = PartitionGardener::Registry.tables.find { |entry| entry[:table_name] == parent_name }
    PartitionGardener::CompositeMaintenance.new(config, job_class_name: "Integration").run!
  end

  it "maintains list parent and hash branch tables without error" do
    insert_composite_row!(parent_name, id: 1, branch: "cached", workspace_id: 10)
    insert_composite_row!(parent_name, id: 2, branch: "workspace", workspace_id: 20)

    expect { run_composite_maintenance! }.not_to raise_error

    expect(partition_attached?(parent_name, default_name(parent_name))).to be(true)
    expect(partition_attached?(parent_name, cached_name)).to be(true)
    expect(partition_attached?(parent_name, workspace_name)).to be(true)
  end

  it "keeps hash remainder partitions attached on branch tables" do
    insert_composite_row!(parent_name, id: 1, branch: "cached", workspace_id: 99)

    run_composite_maintenance!

    expect(partition_attached?(cached_name, "#{cached_name}_a_00")).to be(true)
    expect(partition_attached?(cached_name, "#{cached_name}_a_01")).to be(true)
    expect(partition_attached?(workspace_name, "#{workspace_name}_a_00")).to be(true)
    expect(partition_attached?(workspace_name, "#{workspace_name}_a_01")).to be(true)
  end

  it "run! with the parent table name maintains list and hash branch tables" do
    insert_composite_row!(parent_name, id: 1, branch: "cached", workspace_id: 10)
    insert_composite_row!(parent_name, id: 2, branch: "workspace", workspace_id: 20)

    expect { PartitionGardener.run!(table_name: parent_name, job_class_name: "Integration") }.not_to raise_error

    expect(partition_attached?(parent_name, default_name(parent_name))).to be(true)
    expect(partition_attached?(parent_name, cached_name)).to be(true)
    expect(partition_attached?(parent_name, workspace_name)).to be(true)
    expect(partition_attached?(cached_name, "#{cached_name}_a_00")).to be(true)
    expect(partition_attached?(workspace_name, "#{workspace_name}_a_00")).to be(true)
  end
end

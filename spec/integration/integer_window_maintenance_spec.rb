require "spec_helper"
require_relative "support/database"
require_relative "support/fixtures"

RSpec.describe "integer window maintenance", :integration do
  include PartitionGardener::Integration::Fixtures

  let(:table_name) { unique_table_name("pg_ids") }
  let(:hot_partition) { "#{table_name}_ids_1000_2000" }

  before do
    PartitionGardener::Integration::Database.configure_gardener!
    create_integer_window_table!(table_name, active_id_lo: 0, active_id_width: 10_000)
    register_integer_window!(
      table_name,
      active_id_lo: 0,
      active_id_width: 10_000,
      current_band_size: 1_000,
      split_row_threshold: 2
    )
  end

  after do
    PartitionGardener::RunRecord.clear(table_name)
    drop_table_cascade!(table_name)
  end

  def run_maintenance!
    config = PartitionGardener::Registry.find_by_table_name(table_name)
    PartitionGardener.maintenance_for(config, job_class_name: "Integration").run!
  end

  it "splits a hot id band out of current when row count reaches threshold" do
    insert_row!(table_name, id: 1_500)
    insert_row!(table_name, id: 1_501)

    expect(partition_attached?(table_name, hot_partition)).to be(false)

    run_maintenance!

    expect(partition_attached?(table_name, hot_partition)).to be(true)
    expect(count_rows(hot_partition)).to eq(2)
    expect(count_rows(current_name(table_name), where: "id >= 1000 AND id < 2000")).to eq(0)
  end
end

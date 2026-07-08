require "spec_helper"
require_relative "support/database"
require_relative "support/fixtures"

RSpec.describe "advisory lock", :integration do
  include PartitionGardener::Integration::Fixtures

  let(:today) { Date.new(2026, 7, 5) }
  let(:table_name) { unique_table_name }

  before do
    PartitionGardener::Integration::Database.configure_gardener!(today: today)
    create_sliding_window_table!(table_name, today: today)
    register_sliding_window!(table_name, today: today)
  end

  after do
    drop_table_cascade!(table_name)
  end

  it "allows only one session lock holder at a time" do
    other_connection = ActiveRecord::Base.connection_pool.checkout
    lock_sql = PartitionGardener::AdvisoryLock.send(:lock_expression, other_connection, table_name)

    PartitionGardener::AdvisoryLock.with_table_lock(table_name) do
      acquired = other_connection.execute("SELECT pg_try_advisory_lock(#{lock_sql})").first.values.first
      expect(acquired == true || acquired == "t").to be(false)
    end
  ensure
    ActiveRecord::Base.connection_pool.checkin(other_connection) if other_connection
  end
end

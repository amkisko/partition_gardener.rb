require "spec_helper"

RSpec.describe PartitionGardener do
  describe ".run!" do
    it "wraps each table in its own statement timeout when configured" do
      timeouts = []
      described_class.configure do |configuration|
        configuration.statement_timeout_wrapper = lambda do |timeout, &block|
          timeouts << timeout
          block.call
        end
      end

      PartitionGardener::Registry.register(
        PartitionGardener::Templates.sliding_window_monthly(
          table_name: "events",
          partition_key_column: "occurred_on",
          conflict_key: %w[id occurred_on],
          statement_timeout: 2.minutes
        )
      )
      PartitionGardener::Registry.register(
        PartitionGardener::Templates.sliding_window_monthly(
          table_name: "audits",
          partition_key_column: "created_at",
          conflict_key: %w[id created_at]
        )
      )

      allow(PartitionGardener::Connection).to receive(:table_is_partitioned?).and_return(false)

      described_class.run!(statement_timeout: 5.minutes)

      expect(timeouts).to eq([2.minutes, 5.minutes])
    end

    it "raises RunFailed after continuing past failing tables when continue_on_error is true" do
      PartitionGardener::Registry.register(
        PartitionGardener::Templates.sliding_window_monthly(
          table_name: "events",
          partition_key_column: "occurred_on",
          conflict_key: %w[id occurred_on]
        )
      )
      PartitionGardener::Registry.register(
        PartitionGardener::Templates.sliding_window_monthly(
          table_name: "audits",
          partition_key_column: "created_at",
          conflict_key: %w[id created_at]
        )
      )

      allow(PartitionGardener::Connection).to receive(:table_is_partitioned?).and_return(true)
      attempted_tables = []
      allow(PartitionGardener::AdvisoryLock).to receive(:with_table_lock) do |table_name, &block|
        attempted_tables << table_name
        raise StandardError, "boom" if table_name == "events"

        block.call
      end
      allow(PartitionGardener::DefaultPartition).to receive(:ensure!)
      maintenance = instance_double(PartitionGardener::DateRangeMaintenance, run!: nil)
      allow(described_class).to receive(:maintenance_for).and_return(maintenance)

      expect {
        described_class.run!(continue_on_error: true)
      }.to raise_error(PartitionGardener::RunFailed) do |error|
        expect(error.errors.size).to eq(1)
        expect(error.errors.first.message).to eq("boom")
      end
      expect(attempted_tables).to eq(%w[events audits])
    end
  end
end

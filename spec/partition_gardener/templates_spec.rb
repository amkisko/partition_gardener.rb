require "spec_helper"

RSpec.describe PartitionGardener::Templates do
  let(:quoting_connection) do
    double("connection").tap do |stub|
      allow(stub).to receive(:quote_column_name) { |name| %("#{name}") }
      allow(stub).to receive(:quote) { |value| "'#{value}'" }
    end
  end

  before do
    allow(PartitionGardener::Connection).to receive(:connection).and_return(quoting_connection)
  end

  describe ".premake_monthly" do
    it "builds a legacy premake config" do
      config = described_class.premake_monthly(
        table_name: "audits",
        partition_key_column: "created_at",
        conflict_key: %w[created_at id],
        premake_months: 2
      )

      expect(config[:layout]).to eq(:premake_monthly)
      expect(config[:premake_months]).to eq(2)
      expect(config[:maintenance_backend]).to eq(:gardener)
    end
  end

  describe ".sliding_window_monthly" do
    it "builds a monthly date-range config" do
      config = described_class.sliding_window_monthly(
        table_name: "user_workdays",
        partition_key_column: "date",
        conflict_key: %w[id date],
        active_months: 6
      )

      expect(config[:layout]).to eq(:sliding_window)
      expect(config[:bucket]).to eq(:month)
      expect(config[:active_months]).to eq(6)
      expect(config[:partition_name_format].call(Date.new(2026, 7, 1))).to eq("user_workdays_2026_07")
    end
  end

  describe ".sliding_window_daily" do
    it "builds a daily date-range config" do
      config = described_class.sliding_window_daily(
        table_name: "metrics",
        partition_key_column: "recorded_on",
        conflict_key: %w[id recorded_on],
        active_days: 30
      )

      expect(config[:bucket]).to eq(:day)
      expect(config[:active_days]).to eq(30)
      expect(config[:partition_name_format].call(Date.new(2026, 7, 7))).to eq("metrics_2026_07_07")
    end
  end

  describe ".rolling_current_monthly" do
    it "disables heat splits" do
      config = described_class.rolling_current_monthly(
        table_name: "events",
        partition_key_column: "occurred_on",
        conflict_key: %w[id occurred_on]
      )

      expect(config[:layout]).to eq(:rolling_current)
      expect(config[:split_row_threshold]).to eq(Float::INFINITY)
    end
  end

  describe ".calendar_year" do
    it "builds a yearly date-range config" do
      config = described_class.calendar_year(
        table_name: "events",
        partition_key_column: "occurred_on",
        conflict_key: %w[id occurred_on],
        active_years: 3
      )

      expect(config[:layout]).to eq(:calendar_year)
      expect(config[:bucket]).to eq(:year)
      expect(config[:active_years]).to eq(3)
      expect(config[:partition_name_format].call(Date.new(2026, 7, 1))).to eq("events_2026")
    end
  end

  describe ".list_split" do
    it "normalizes branch predicates into where_condition at registration" do
      config = described_class.list_split(
        table_name: "repository_packages",
        conflict_key: %w[id],
        partition_key_column: "branch",
        branches: [
          {name: "cached", value: "cached"},
          {name: "workspace", value: "workspace"}
        ]
      )

      expect(config[:branches].map { |branch| branch[:where_condition] }).to eq(
        [%("branch" = 'cached'), %("branch" = 'workspace')]
      )
    end
  end

  describe ".composite_list_hash" do
    it "expands into list parent and hash branch tables" do
      config = described_class.composite_list_hash(
        parent_table: "repository_packages",
        discriminator_column: "branch",
        conflict_key: %w[id],
        branches: [
          {
            name: "cached",
            value: "cached",
            where_condition: "branch = 'cached'",
            partition_key_column: "workspace_id",
            hash_modulus: 8
          },
          {
            name: "workspace",
            value: "workspace",
            where_condition: "branch = 'workspace'",
            partition_key_column: "workspace_id",
            hash_modulus: 16
          }
        ]
      )

      expanded = described_class.expand(config)
      expect(expanded.map { |entry| entry[:table_name] }).to eq(
        %w[repository_packages repository_packages_cached repository_packages_workspace]
      )
      expect(expanded[0][:layout]).to eq(:list_split)
      expect(expanded[1][:layout]).to eq(:hash_branches)
      expect(expanded[1][:hash_modulus]).to eq(8)
      expect(expanded[1]).not_to have_key(:split_row_threshold)
    end
  end

  describe ".composite_list_range" do
    it "expands into list parent and range branch tables" do
      config = described_class.composite_list_range(
        parent_table: "branch_events",
        discriminator_column: "branch",
        conflict_key: %w[id],
        branches: [
          {
            name: "cached",
            value: "cached",
            where_condition: "branch = 'cached'",
            partition_key_column: "occurred_on",
            active_months: 6
          }
        ]
      )

      expanded = described_class.expand(config)
      expect(expanded.map { |entry| entry[:table_name] }).to eq(%w[branch_events branch_events_cached])
      expect(expanded[0][:layout]).to eq(:list_split)
      expect(expanded[1][:layout]).to eq(:sliding_window)
      expect(expanded[1][:bucket]).to eq(:month)
    end
  end

  describe ".composite_range_hash" do
    it "expands into range parent and hash branch tables" do
      config = described_class.composite_range_hash(
        parent_table: "events",
        partition_key_column: "occurred_on",
        conflict_key: %w[id occurred_on],
        branches: [
          {
            name: "shard_a",
            partition_key_column: "workspace_id",
            hash_modulus: 4
          }
        ]
      )

      expanded = described_class.expand(config)
      expect(expanded.map { |entry| entry[:table_name] }).to eq(%w[events events_shard_a])
      expect(expanded[0][:layout]).to eq(:sliding_window)
      expect(expanded[1][:layout]).to eq(:hash_branches)
    end
  end
end

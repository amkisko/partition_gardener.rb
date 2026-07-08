require "spec_helper"

RSpec.describe PartitionGardener::Registry do
  before do
    described_class.reset!
  end

  describe ".register_template" do
    it "builds from a named template and registers like .register" do
      config = described_class.register_template(
        :sliding_window_monthly,
        table_name: "events",
        partition_key_column: "occurred_on",
        conflict_key: %w[id occurred_on],
        active_months: 12
      )

      expect(config[:table_name]).to eq("events")
      expect(config[:layout]).to eq(:sliding_window)
      expect(config[:active_months]).to eq(12)
      expect(described_class.find_by_table_name("events")).to eq(config)
    end

    it "raises for unknown template names" do
      expect {
        described_class.register_template(:not_a_template, table_name: "events")
      }.to raise_error(ArgumentError, /unknown template/)
    end
  end

  describe ".configs_for_table" do
    it "expands composite registrations into all branch tables for the parent name" do
      described_class.register(
        PartitionGardener::Templates.composite_list_hash(
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
      )

      configs = described_class.configs_for_table("repository_packages")

      expect(configs.map { |config| config[:table_name] }).to eq(
        %w[repository_packages repository_packages_cached repository_packages_workspace]
      )
    end

    it "returns a single sliding-window config for a non-composite table name" do
      described_class.register(
        PartitionGardener::Templates.sliding_window_monthly(
          table_name: "events",
          partition_key_column: "occurred_on",
          conflict_key: %w[id occurred_on]
        )
      )

      configs = described_class.configs_for_table("events")

      expect(configs.map { |config| config[:table_name] }).to eq(%w[events])
    end
  end

  describe ".hot_switch_partition_config" do
    it "builds premake lambdas from a registered sliding window table" do
      described_class.register(
        PartitionGardener::Templates.sliding_window_monthly(
          table_name: "events",
          partition_key_column: "occurred_on",
          conflict_key: %w[id occurred_on]
        )
      )

      config = described_class.hot_switch_partition_config("events")
      today = Date.new(2026, 7, 5)

      expect(config[:partitions_to_create].call(today)).to eq(
        [Date.new(2026, 7, 1), Date.new(2026, 8, 1)]
      )
      expect(config[:partition_name_format].call(today.beginning_of_month)).to eq("events_2026_07")
    end
  end
end

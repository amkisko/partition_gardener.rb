require "spec_helper"

RSpec.describe PartitionGardener::Strategy::IntegerRange do
  subject(:strategy) { described_class.new(config) }

  before do
    allow(PartitionGardener::Connection).to receive_messages(attached_partitions: [], partition_exists?: false, partition_attached?: false)
  end

  let(:config) do
    {
      table_name: "events",
      layout: :integer_window,
      partition_key_column: "id",
      conflict_key: %w[id],
      active_id_lo: 0,
      active_id_width: 5_000_000,
      current_band_size: 1_000_000
    }
  end

  it "builds current, future, and optional hot id bands" do
    plan = strategy.build_plan

    expect(plan.segments.map(&:name)).to eq(%w[events_current events_future])
    expect(plan.segments.first.range_start).to eq(0)
    expect(plan.segments.first.range_end).to eq(5_000_000)
    expect(plan.segments.last.for_values_clause(strategy)).to eq("FROM (5000000) TO (MAXVALUE)")
  end

  it "splits hot id bands inside the current zone" do
    plan = described_class.new(
      config.merge(split_row_threshold: 50)
    ).tap do |hot_strategy|
      allow(hot_strategy).to receive(:collect_heatmap).and_return(
        {bucket_counts: {1_000_000 => 100}, default_rows: 0, dedicated_partition_counts: {}}
      )
    end.build_plan

    hot_segment = plan.segments.find { |segment| segment.name == "events_ids_1000000_2000000" }
    expect(hot_segment).not_to be_nil
    expect(hot_segment.for_values_clause(strategy)).to eq("FROM (1000000) TO (2000000)")
  end

  it "refines hot buckets from dedicated partition heatmap counts without a second full count query" do
    window = {start: 0, end: 5_000_000}
    heatmap = {
      bucket_counts: {1_000_000 => 50_000},
      dedicated_partition_counts: {1_000_000 => 150_000},
      default_rows: 0
    }

    allow(strategy).to receive(:hot_bucket_partitions_in_window).with(window).and_return(
      [["events_ids_1000000_2000000", 1_000_000]]
    )

    expect(PartitionGardener::Connection).not_to receive(:count_rows_in_partition_table)

    expect(strategy.hot_buckets_in_window(heatmap, window)).to eq([1_000_000])
  end
end

RSpec.describe PartitionGardener::Strategy::DateRange do
  subject(:strategy) { described_class.new(config) }

  let(:config) do
    {
      table_name: "events",
      layout: :sliding_window,
      partition_key_column: "occurred_on",
      conflict_key: %w[id occurred_on],
      split_row_threshold: 100_000
    }
  end

  let(:window) { {start: Date.new(2025, 7, 1), end: Date.new(2026, 10, 1)} }
  let(:hot_bucket) { Date.new(2026, 9, 1) }

  it "refines hot buckets from dedicated partition heatmap counts without a second full count query" do
    heatmap = {
      bucket_counts: {hot_bucket => 50_000},
      dedicated_partition_counts: {hot_bucket => 150_000},
      default_rows: 0
    }

    allow(strategy).to receive(:hot_bucket_partitions_in_window).with(window).and_return(
      [["events_2026_09", hot_bucket]]
    )

    expect(PartitionGardener::Connection).not_to receive(:count_rows_in_partition_table)

    expect(strategy.hot_buckets_in_window(heatmap, window)).to eq([hot_bucket])
  end
end

RSpec.describe PartitionGardener::Strategy::HashBranches do
  subject(:strategy) { described_class.new(config) }

  before do
    allow(PartitionGardener::Connection).to receive_messages(attached_partitions: [], partition_exists?: false, partition_attached?: false)
  end

  let(:config) do
    {
      table_name: "repository_packages_cached",
      layout: :hash_branches,
      partition_key_column: "workspace_id",
      conflict_key: %w[id workspace_id],
      hash_modulus: 4
    }
  end

  it "builds archive and current hash remainder partitions for every bucket" do
    allow(strategy).to receive(:collect_heatmap).and_return({bucket_counts: {}, default_rows: 0})

    plan = strategy.build_plan

    expect(plan.segments.map(&:name)).to eq(
      %w[
        repository_packages_cached_a_00
        repository_packages_cached_a_01
        repository_packages_cached_a_02
        repository_packages_cached_a_03
      ]
    )
    expect(plan.segments.first.for_values_clause(strategy)).to eq("WITH (modulus 4, remainder 0)")
  end

  it "promotes hot remainders into the current zone" do
    plan = described_class.new(config.merge(split_row_threshold: 10)).tap do |hot_strategy|
      allow(hot_strategy).to receive(:collect_heatmap).and_return(
        {bucket_counts: {2 => 100}, default_rows: 0}
      )
    end.build_plan

    expect(plan.hot_buckets).to eq([2])
    expect(plan.segments.map(&:name)).to include("repository_packages_cached_h_02")
  end

  it "uses the default split threshold when the config sets split_row_threshold to nil" do
    allow(PartitionGardener::HashRouting).to receive(:collect_bucket_counts).and_return({1 => 1})

    expect do
      described_class.new(config.merge(split_row_threshold: nil)).build_plan
    end.not_to raise_error
  end

  it "builds hot buckets from heatmap counts without re-counting attached partitions" do
    allow(PartitionGardener::HashRouting).to receive(:collect_bucket_counts).and_return({2 => 150_000})
    allow(PartitionGardener::Connection).to receive(:partition_exists?).and_return(false)

    expect(PartitionGardener::Connection).not_to receive(:count_rows_in_partition_table)

    plan = described_class.new(config.merge(split_row_threshold: 100_000)).build_plan

    expect(plan.hot_buckets).to eq([2])
  end
end

RSpec.describe PartitionGardener::Strategy do
  describe ".for" do
    it "requires a default partition for range and list strategies" do
      [
        PartitionGardener::Templates.integer_window(
          table_name: "events",
          partition_key_column: "id",
          conflict_key: %w[id]
        ),
        PartitionGardener::Templates.sliding_window_monthly(
          table_name: "user_workdays",
          partition_key_column: "date",
          conflict_key: %w[id date]
        ),
        PartitionGardener::Templates.list_split(
          table_name: "repository_packages",
          conflict_key: %w[id],
          branches: [{name: "cached", value: "cached", where_condition: "branch = 'cached'"}]
        )
      ].each do |config|
        expect(described_class.for(config).default_partition_required?).to be(true)
      end
    end

    it "does not require a default partition for hash strategies" do
      config = PartitionGardener::Templates.hash_branches(
        table_name: "packages",
        partition_key_column: "workspace_id",
        conflict_key: %w[id workspace_id]
      )

      expect(described_class.for(config).default_partition_required?).to be(false)
    end
  end
end

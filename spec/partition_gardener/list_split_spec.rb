require "spec_helper"

RSpec.describe PartitionGardener::Strategy::ListSplit do
  subject(:strategy) { described_class.new(config) }

  let(:config) do
    PartitionGardener::Templates.list_split(
      table_name: "repository_packages",
      conflict_key: %w[id],
      branches: [
        {
          name: "cached",
          value: "cached",
          where_condition: "branch = 'cached'"
        },
        {
          name: "workspace",
          value: "workspace",
          where_condition: "branch = 'workspace'"
        }
      ]
    )
  end

  it "builds fixed list branch segments" do
    plan = strategy.build_plan

    expect(plan.segments.map(&:name)).to eq(
      %w[repository_packages_cached repository_packages_workspace]
    )
    expect(plan.segments.first.for_values_clause(strategy)).to eq("IN ('cached')")
    expect(plan.segments.last.for_values_clause(strategy)).to eq("IN ('workspace')")
  end
end

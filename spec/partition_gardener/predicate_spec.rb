require "spec_helper"

RSpec.describe PartitionGardener::Predicate do
  let(:connection) do
    double("connection").tap do |stub|
      allow(stub).to receive(:quote_column_name) { |name| %("#{name}") }
      allow(stub).to receive(:quote) { |value| "'#{value}'" }
    end
  end

  describe ".render" do
    it "renders equality on a quoted column and value" do
      sql = described_class.render(
        {column: "branch", operator: "eq", value: "cached"},
        connection: connection
      )

      expect(sql).to eq(%("branch" = 'cached'))
    end

    it "renders inequality" do
      sql = described_class.render(
        {column: "status", operator: "ne", value: "archived"},
        connection: connection
      )

      expect(sql).to eq(%("status" <> 'archived'))
    end

    it "renders IS NULL" do
      sql = described_class.render(
        {column: "branch", operator: "is_null"},
        connection: connection
      )

      expect(sql).to eq(%("branch" IS NULL))
    end

    it "rejects invalid column names" do
      expect {
        described_class.render(
          {column: "branch; DROP TABLE", operator: "eq", value: "x"},
          connection: connection
        )
      }.to raise_error(ArgumentError, /column/)
    end

    it "rejects unknown operators" do
      expect {
        described_class.render(
          {column: "branch", operator: "like", value: "%"},
          connection: connection
        )
      }.to raise_error(ArgumentError, /operator/)
    end
  end

  describe ".normalize_branch!" do
    it "builds where_condition from a structured predicate" do
      branch = described_class.normalize_branch!(
        {name: "cached", value: "cached", predicate: {column: "branch", operator: "eq", value: "cached"}},
        discriminator_column: "branch",
        connection: connection
      )

      expect(branch[:where_condition]).to eq(%("branch" = 'cached'))
      expect(branch).not_to have_key(:predicate)
    end

    it "infers equality from branch value and discriminator column" do
      branch = described_class.normalize_branch!(
        {name: "workspace", value: "workspace"},
        discriminator_column: "branch",
        connection: connection
      )

      expect(branch[:where_condition]).to eq(%("branch" = 'workspace'))
    end

    it "keeps a legacy where_condition string" do
      branch = described_class.normalize_branch!(
        {name: "cached", value: "cached", where_condition: "branch = 'cached'"},
        discriminator_column: "branch"
      )

      expect(branch[:where_condition]).to eq("branch = 'cached'")
    end

    it "requires predicate, where_condition, or inferable value" do
      expect {
        described_class.normalize_branch!(
          {name: "cached", value: "cached"},
          discriminator_column: nil
        )
      }.to raise_error(ArgumentError, /predicate/)
    end
  end
end

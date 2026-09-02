require "spec_helper"

RSpec.describe PartitionGardener::ChildColumnAlign do
  let(:connection) { double("connection") }
  let(:align) { described_class.new(connection: connection) }
  let(:executed_sql) { [] }
  let(:parent_columns) do
    [
      column_row("id", "bigint", not_null: true),
      column_row("occurred_on", "date", not_null: true),
      column_row("extra_attr", "text", not_null: false)
    ]
  end
  let(:child_columns) do
    [
      column_row("id", "bigint", not_null: true),
      column_row("occurred_on", "date", not_null: true)
    ]
  end
  let(:catalog) { {row_count: 0} }
  let(:unattached_names) { ["events_2024_06"] }

  before do
    allow(connection).to receive(:quote_table_name) { |name| %("#{name}") }
    allow(connection).to receive(:quote_column_name) { |name| %("#{name}") }
    allow(connection).to receive(:quote) { |value| "'#{value}'" }
    allow(PartitionGardener.configuration).to receive(:schema_name).and_return("public")
    allow(connection).to receive(:execute) do |sql|
      executed_sql << sql
      catalog_result(sql)
    end
  end

  it "adds missing ordinary parent columns on the child" do
    align.align!("events", "events_2024_06")

    expect(executed_sql.join).to include('ALTER TABLE "events_2024_06" ADD COLUMN "extra_attr" text')
  end

  it "copies a default and sets NOT NULL when the parent column is NOT NULL" do
    parent_columns << column_row(
      "extra_flag",
      "text",
      not_null: true,
      default_expression: "'unset'::text"
    )

    align.align!("events", "events_2024_06")

    sql = executed_sql.join
    expect(sql).to include(%(ADD COLUMN "extra_flag" text DEFAULT 'unset'::text))
    expect(sql).to include(%(ALTER COLUMN "extra_flag" SET NOT NULL))
  end

  it "does not set NOT NULL when the child has rows and the column has no default" do
    parent_columns << column_row("extra_flag", "text", not_null: true)
    catalog[:row_count] = 3

    align.align!("events", "events_2024_06")

    expect(executed_sql.join).to include(%(ADD COLUMN "extra_flag" text))
    expect(executed_sql.join).not_to include("SET NOT NULL")
  end

  it "skips identity and generated parent columns" do
    parent_columns << column_row("id_seq", "bigint", identity: "a")
    parent_columns << column_row("label", "text", generated: "s")

    align.align!("events", "events_2024_06")

    sql = executed_sql.join
    expect(sql).not_to include("id_seq")
    expect(sql).not_to include('"label"')
  end

  it "warns when an unattached child lags the parent" do
    warnings = align.lagging_child_warnings("events")

    expect(warnings).to eq(
      ["child events_2024_06 is missing column extra_attr from parent events"]
    )
  end

  def column_row(name, type, not_null: false, default_expression: nil, identity: "", generated: "")
    {
      "name" => name,
      "type" => type,
      "not_null" => not_null,
      "default_expression" => default_expression,
      "identity" => identity,
      "generated" => generated
    }
  end

  def catalog_result(sql)
    if sql.include?("pg_attribute")
      table_name = sql[/table_class\.relname = '([^']+)'/, 1]
      (table_name == "events") ? parent_columns : child_columns
    elsif sql.include?("starts_with")
      unattached_names.map { |name| {"relname" => name} }
    elsif sql.include?("COUNT(*)")
      [{"count" => catalog[:row_count]}]
    else
      []
    end
  end
end

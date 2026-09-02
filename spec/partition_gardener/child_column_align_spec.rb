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

    expect(executed_sql.grep(/ALTER TABLE/).join).to include('ADD COLUMN "extra_attr" text')
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
    expect(sql).to include(%(ADD COLUMN "extra_flag" text DEFAULT 'unset'::text NOT NULL))
  end

  it "preserves a parent column collation" do
    parent_columns << column_row(
      "localized_label",
      "text",
      collation_schema: "pg_catalog",
      collation_name: "C"
    )

    align.align!("events", "events_2024_06")

    expect(executed_sql.join).to include(
      %(ADD COLUMN "localized_label" text COLLATE "pg_catalog"."C")
    )
  end

  it "adds all missing columns atomically with the parent NOT NULL contract" do
    parent_columns << column_row("extra_flag", "text", not_null: true)

    align.align!("events", "events_2024_06")

    alter_statements = executed_sql.grep(/ALTER TABLE/)
    expect(alter_statements.size).to eq(1)
    expect(alter_statements.first).to include(%(ADD COLUMN "extra_attr" text))
    expect(alter_statements.first).to include(%(ADD COLUMN "extra_flag" text NOT NULL))
    expect(executed_sql.join).not_to include("COUNT(*)")
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

  it "loads parent and child columns in one catalog query" do
    unattached_names.concat(%w[events_2024_07 events_2024_08])

    align.lagging_child_warnings("events")

    catalog_queries = executed_sql.grep(/pg_attribute/)
    expect(catalog_queries.size).to eq(1)
  end

  it "filters unrelated prefixed tables before loading their columns" do
    unattached_names << "events_backup"

    warnings = align.lagging_child_warnings(
      "events",
      candidate_table: ->(name) { name != "events_backup" }
    )

    expect(warnings.join).not_to include("events_backup")
    expect(executed_sql.grep(/pg_attribute/).join).not_to include("events_backup")
  end

  def column_row(
    name,
    type,
    not_null: false,
    default_expression: nil,
    identity: "",
    generated: "",
    collation_schema: nil,
    collation_name: nil
  )
    {
      "name" => name,
      "type" => type,
      "not_null" => not_null,
      "default_expression" => default_expression,
      "identity" => identity,
      "generated" => generated,
      "collation_schema" => collation_schema,
      "collation_name" => collation_name
    }
  end

  def catalog_result(sql)
    if sql.include?("pg_attribute")
      names_clause = sql[/table_class\.relname IN \(([^)]+)\)/, 1]
      names = names_clause.scan(/'([^']+)'/).flatten
      names.flat_map do |table_name|
        columns = (table_name == "events") ? parent_columns : child_columns
        columns.map { |column| column.merge("table_name" => table_name) }
      end
    elsif sql.include?("starts_with")
      unattached_names.map { |name| {"relname" => name} }
    else
      []
    end
  end
end

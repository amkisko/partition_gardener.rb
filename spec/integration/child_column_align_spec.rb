require "spec_helper"
require_relative "support/database"
require_relative "support/fixtures"

RSpec.describe "child column align on attach", :integration do
  include PartitionGardener::Integration::Fixtures

  let(:connection) { PartitionGardener::Integration::Database.connection }
  let(:table_name) { unique_table_name }
  let(:child_name) { "#{table_name}_2024_06" }
  let(:executor) { PartitionGardener::Executor.new(connection: connection, batch_size: 100) }

  before do
    PartitionGardener::Integration::Database.configure_gardener!
    connection.execute(<<~SQL)
      CREATE TABLE #{quote_table(table_name)} (
        id bigint NOT NULL,
        occurred_on date NOT NULL,
        PRIMARY KEY (id, occurred_on)
      ) PARTITION BY RANGE (occurred_on)
    SQL
    connection.execute(<<~SQL)
      CREATE TABLE #{quote_table(default_name(table_name))} PARTITION OF #{quote_table(table_name)} DEFAULT
    SQL
    connection.execute(<<~SQL)
      CREATE TABLE #{quote_table(child_name)} (
        LIKE #{quote_table(table_name)} INCLUDING ALL
      )
    SQL
    connection.execute(<<~SQL)
      ALTER TABLE #{quote_table(table_name)} ADD COLUMN extra_attr text
    SQL
    PartitionGardener::Registry.register(
      PartitionGardener::Templates.premake_monthly(
        table_name: table_name,
        partition_key_column: "occurred_on",
        conflict_key: %w[id occurred_on],
        premake_months: 1
      )
    )
  end

  after do
    drop_table_cascade!(child_name)
    drop_table_cascade!(table_name)
  end

  it "adds missing ordinary parent columns then attaches a LIKE child" do
    expect(table_column_names(child_name)).not_to include("extra_attr")

    warnings = PartitionGardener::Audit.call(table_name).warnings
    expect(warnings).to include(
      "child #{child_name} is missing column extra_attr from parent #{table_name}"
    )

    executor.attach_partition(table_name, child_name, "FROM ('2024-06-01') TO ('2024-07-01')")

    expect(partition_attached?(table_name, child_name)).to be(true)
    expect(table_column_names(child_name)).to include("extra_attr")
  end

  it "leaves a lagging LIKE child unattached when align is disabled" do
    fail_fast = PartitionGardener::Executor.new(
      connection: connection,
      batch_size: 100,
      align_child_columns: false
    )

    expect {
      fail_fast.attach_partition(table_name, child_name, "FROM ('2024-06-01') TO ('2024-07-01')")
    }.to raise_error(ActiveRecord::StatementInvalid, /DatatypeMismatch|tuple descriptor/i)

    expect(partition_attached?(table_name, child_name)).to be(false)
    expect(table_column_names(child_name)).not_to include("extra_attr")
  end

  it "aligns an existing LIKE table before attach after CREATE TABLE IF NOT EXISTS" do
    executor.ensure_detached_partition_table!(
      table_name,
      child_name,
      conflict_key: %w[id occurred_on extra_attr]
    )

    expect(table_column_names(child_name)).to include("extra_attr")

    executor.attach_partition(table_name, child_name, "FROM ('2024-06-01') TO ('2024-07-01')")

    expect(partition_attached?(table_name, child_name)).to be(true)
  end

  it "preserves a non-default collation when adding a missing column" do
    connection.execute(<<~SQL)
      ALTER TABLE #{quote_table(table_name)} ADD COLUMN localized_label text COLLATE "C"
    SQL

    executor.attach_partition(table_name, child_name, "FROM ('2024-06-01') TO ('2024-07-01')")

    expect(partition_attached?(table_name, child_name)).to be(true)
  end

  it "fails before mutating a populated child for a NOT NULL column without a default" do
    connection.execute(<<~SQL)
      INSERT INTO #{quote_table(child_name)} (id, occurred_on) VALUES (1, '2024-06-15')
    SQL
    connection.execute(<<~SQL)
      ALTER TABLE #{quote_table(table_name)} ADD COLUMN required_text text NOT NULL
    SQL

    expect {
      executor.attach_partition(table_name, child_name, "FROM ('2024-06-01') TO ('2024-07-01')")
    }.to raise_error(ActiveRecord::StatementInvalid, /required_text.*null|contains null values/i)

    expect(table_column_names(child_name)).not_to include("extra_attr", "required_text")
  end

  it "does not audit an unrelated table that only shares the parent prefix" do
    unrelated_name = "#{table_name}_backup"
    connection.execute(<<~SQL)
      CREATE TABLE #{quote_table(unrelated_name)} (id bigint)
    SQL

    warnings = PartitionGardener::Audit.call(table_name).warnings

    expect(warnings.join).not_to include(unrelated_name)
  ensure
    drop_table_cascade!(unrelated_name)
  end

  it "keeps prefix discovery for a custom partition name formatter" do
    custom_child_name = "#{table_name}_period_june"
    connection.execute(<<~SQL)
      CREATE TABLE #{quote_table(custom_child_name)} (LIKE #{quote_table(child_name)} INCLUDING ALL)
    SQL
    custom_config = PartitionGardener::Templates.premake_monthly(
      table_name: table_name,
      partition_key_column: "occurred_on",
      conflict_key: %w[id occurred_on],
      partition_name_format: ->(_identifier) { custom_child_name }
    )

    warnings = PartitionGardener::Audit.call(table_name, config: custom_config).warnings

    expect(warnings.join).to include(custom_child_name)
  ensure
    drop_table_cascade!(custom_child_name)
  end

  it "sets NOT NULL on a missing parent column when the child is empty" do
    connection.execute(<<~SQL)
      ALTER TABLE #{quote_table(table_name)} ADD COLUMN extra_flag text NOT NULL DEFAULT 'unset'
    SQL

    executor.attach_partition(table_name, child_name, "FROM ('2024-06-01') TO ('2024-07-01')")

    expect(column_not_null?(child_name, "extra_flag")).to be(true)
    expect(column_default(child_name, "extra_flag")).to include("unset")
  end

  it "does not drop extra child columns when aligning before attach" do
    connection.execute(<<~SQL)
      ALTER TABLE #{quote_table(child_name)} ADD COLUMN leftover_note text
    SQL

    expect {
      executor.attach_partition(table_name, child_name, "FROM ('2024-06-01') TO ('2024-07-01')")
    }.to raise_error(ActiveRecord::StatementInvalid, /DatatypeMismatch|tuple descriptor/i)

    expect(table_column_names(child_name)).to include("leftover_note")
    expect(table_column_names(child_name)).to include("extra_attr")
    expect(column_type(child_name, "id")).to eq("bigint")
  end

  def table_column_names(name)
    connection.execute(<<~SQL).map { |row| row["column_name"] }
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = #{connection.quote(name)}
      ORDER BY ordinal_position
    SQL
  end

  def column_not_null?(name, column_name)
    row = connection.execute(<<~SQL).first
      SELECT is_nullable
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = #{connection.quote(name)}
        AND column_name = #{connection.quote(column_name)}
    SQL
    row && row["is_nullable"] == "NO"
  end

  def column_default(name, column_name)
    row = connection.execute(<<~SQL).first
      SELECT column_default
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = #{connection.quote(name)}
        AND column_name = #{connection.quote(column_name)}
    SQL
    row && row["column_default"].to_s
  end

  def column_type(name, column_name)
    row = connection.execute(<<~SQL).first
      SELECT data_type
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = #{connection.quote(name)}
        AND column_name = #{connection.quote(column_name)}
    SQL
    row && row["data_type"]
  end
end

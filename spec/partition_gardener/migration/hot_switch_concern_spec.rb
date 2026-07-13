require "spec_helper"

RSpec.describe PartitionGardener::Migration::HotSwitchConcern do
  let(:migration_class) do
    Class.new do
      include PartitionGardener::Migration::HotSwitchConcern

      def initialize(config)
        @config = config
      end

      def hot_switch_config
        @config
      end

      def connection
        @connection ||= Object.new.tap do |connection|
          def connection.quote(value)
            "'#{value}'"
          end

          def connection.quote_column_name(name)
            %("#{name}")
          end

          def connection.quote_table_name(name)
            %("#{name}")
          end

          def connection.table_exists?(name)
            @table_exists ||= {}
            @table_exists.fetch(name, false)
          end

          def connection.mark_table_exists!(name)
            @table_exists ||= {}
            @table_exists[name] = true
          end
        end
      end

      def say(_message)
      end

      def transaction
        yield
      end
    end
  end

  let(:migration) do
    migration_class.new(
      current_table: "events",
      partitioned_table: "events_partitioned",
      partition_key_column: "occurred_on",
      conflict_key: %w[id occurred_on],
      sync_batch_size: 2
    )
  end

  let(:executed_sql) { [] }

  before do
    PartitionGardener.configure do |configuration|
      configuration.today_resolver = -> { Date.new(2026, 7, 5) }
      configuration.schema_name = "public"
    end

    allow(migration).to receive(:table_columns).and_return(%w[id occurred_on updated_at])

    insert_results = [2, 2, 1, 0]
    allow(migration.connection).to receive(:execute) do |sql|
      executed_sql << sql
      if sql.include?("SELECT COUNT")
        [{"count" => "5"}]
      elsif sql.include?("pg_get_serial_sequence")
        []
      else
        Struct.new(:cmd_tuples).new(insert_results.shift)
      end
    end
  end

  it "syncs delta rows in batches instead of one unbounded insert" do
    migration.sync_delta_data

    insert_statements = executed_sql.grep(/INSERT INTO/)
    expect(insert_statements.length).to be > 1
    expect(insert_statements).to all(include("LIMIT 2"))
  end

  it "resolves swapped sync tables from config names" do
    migration.sync_delta_data(swapped: true)

    expect(executed_sql.join).to include('"events_old"')
    expect(executed_sql.join).to include('"events"')
    expect(executed_sql.join).not_to include('"events_partitioned"')
  end

  it "uses explicit source and target tables when provided" do
    migration.sync_delta_data(source_table: "legacy", target_table: "shadow")

    expect(executed_sql.join).to include('"legacy"')
    expect(executed_sql.join).to include('"shadow"')
  end

  it "sleeps between sync batches when sleep_seconds is set" do
    allow(migration).to receive(:sleep)
    migration.sync_delta_data(sleep_seconds: 0.01)

    expect(migration).to have_received(:sleep).with(0.01).at_least(:once)
  end

  it "sets lock_timeout at the start of hot_switch_tables when configured" do
    migration = migration_class.new(
      current_table: "events",
      partitioned_table: "events_partitioned",
      partition_key_column: "occurred_on",
      swap_lock_timeout: "5s"
    )

    allow(migration).to receive_messages(fetch_partitions: [], serial_sequence_pairs: [])
    allow(migration).to receive(:remove_write_block_trigger)
    allow(migration.connection).to receive(:execute) { |sql| executed_sql << sql }

    migration.hot_switch_tables

    expect(executed_sql).to include(a_string_matching(/SET LOCAL lock_timeout = '5s'/))
  end

  it "skips lock_timeout when swap_lock_timeout is nil" do
    migration = migration_class.new(
      current_table: "events",
      partitioned_table: "events_partitioned",
      partition_key_column: "occurred_on",
      swap_lock_timeout: nil
    )

    allow(migration).to receive_messages(fetch_partitions: [], serial_sequence_pairs: [])
    allow(migration).to receive(:remove_write_block_trigger)
    allow(migration.connection).to receive(:execute) { |sql| executed_sql << sql }

    migration.hot_switch_tables

    expect(executed_sql).not_to include(a_string_matching(/lock_timeout/))
  end

  it "repoints serial sequences after hot_switch_tables renames" do
    migration = migration_class.new(
      current_table: "events",
      partitioned_table: "events_partitioned",
      partition_key_column: "occurred_on",
      swap_lock_timeout: nil
    )

    allow(migration).to receive(:fetch_partitions).and_return([])
    allow(migration).to receive(:remove_write_block_trigger)
    allow(migration).to receive(:serial_sequence_pairs).with("events").and_return([["id", "public.events_id_seq"]])
    allow(migration.connection).to receive(:execute) { |sql| executed_sql << sql }

    migration.hot_switch_tables

    expect(executed_sql).to include(a_string_matching(/ALTER SEQUENCE public\.events_id_seq OWNED BY/))
  end

  it "analyzes shadow partition children and parent" do
    allow(migration).to receive(:fetch_partitions).with("events_partitioned").and_return(%w[events_partitioned_2026_07])
    allow(migration.connection).to receive(:execute) { |sql| executed_sql << sql }

    migration.analyze_shadow_partitions!

    expect(executed_sql).to include("ANALYZE events_partitioned_2026_07")
    expect(executed_sql).to include('ANALYZE "events_partitioned"')
  end

  it "runs sql through the configured connection instead of ActiveRecord::Migration#execute" do
    require "active_record"

    migration = Class.new(ActiveRecord::Migration[7.2]) do
      include PartitionGardener::Migration::HotSwitchConcern

      const_set(:HOT_SWITCH_CONFIG, {
        current_table: "events",
        partitioned_table: "events_partitioned",
        partition_key_column: "occurred_on"
      })
    end.new

    connection = instance_double(
      "Connection",
      quote: "'public'",
      quote_column_name: '"id"',
      quote_table_name: '"events"'
    )
    allow(connection).to receive(:execute).and_return([{"column_name" => "id"}])

    PartitionGardener.configure do |configuration|
      configuration.schema_name = "public"
      configuration.connection_resolver = -> { connection }
    end

    expect(migration.send(:table_columns, "events")).to eq(["id"])
    expect(connection).to have_received(:execute)
  end
end

module PartitionGardener
  module Migration
    # Hot-switch from a live non-partitioned table to a declarative partitioned shadow table.
    #
    # Recommended at switch time:
    # - create default + minimal premake (months_ahead: 1)
    # - run nightly PartitionGardener maintenance after cutover for sliding-window layout
    #
    # +partition_config+ may be an inline hash or resolved from Registry via
    # +PartitionGardener::Registry.hot_switch_partition_config+.
    module HotSwitchConcern
      DEFAULT_SWAP_LOCK_TIMEOUT = "5s"

      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def hot_switch_partition_config(table_name)
          PartitionGardener::Registry.hot_switch_partition_config(table_name)
        end
      end

      def ensure_future_partitions_exist(months_ahead: 1)
        config = hot_switch_config
        partition_config = resolve_partition_config(config)
        return unless partition_config

        if months_ahead > 3
          say "Warning: months_ahead=#{months_ahead} creates many partitions at switch time; prefer 1 and let PartitionGardener maintain the sliding window"
        end

        today = PartitionGardener.configuration.today
        partitions_to_create = partition_config[:partitions_to_create].call(today)
        additional_months = (1..months_ahead).map { |month_offset| DateCalendar.add_months(today, month_offset) }
        all_months = (partitions_to_create + additional_months).uniq.sort

        partition_name_format = partition_config[:partition_name_format]
        partition_definition = partition_config[:partition_definition]
        partitioned_table = config[:partitioned_table]
        current_table = config[:current_table]

        all_months.each do |identifier|
          partition_name = partition_name_format.call(identifier).gsub(/^#{current_table}_/, "#{partitioned_table}_")
          next if connection.table_exists?(partition_name)

          for_values_clause = partition_definition.call(identifier)
          sql = <<~SQL
            CREATE TABLE IF NOT EXISTS #{quoted_table(partition_name)} PARTITION OF #{quoted_table(partitioned_table)}
            FOR VALUES #{for_values_clause}
          SQL
          execute(sql)
          say "Created partition #{partition_name}"
        end

        say "Ensured #{all_months.size} partitions exist (including #{months_ahead} months ahead)"
      end

      def analyze_shadow_partitions!
        config = hot_switch_config
        partitioned_table = config[:partitioned_table]

        say "Analyzing shadow partitions for #{partitioned_table}"

        fetch_partitions(partitioned_table).each do |partition|
          execute "ANALYZE #{partition}"
          say "Analyzed #{partition}"
        end

        execute "ANALYZE #{quoted_table(partitioned_table)}"
        say "Analyzed #{partitioned_table}"
      end

      def add_write_block_trigger(table_name)
        trigger_name = "#{table_name}_write_block_trigger"
        function_name = "#{table_name}_write_block_function"

        sql = <<~SQL
          CREATE OR REPLACE FUNCTION #{function_name}()
          RETURNS TRIGGER AS $$
          BEGIN
            RAISE EXCEPTION 'Table % is read-only. Write operations are blocked during hot switch.', '#{table_name}';
          END;
          $$ LANGUAGE plpgsql;
        SQL
        execute(sql)

        execute "DROP TRIGGER IF EXISTS #{trigger_name} ON #{quoted_table(table_name)}"
        sql = <<~SQL
          CREATE TRIGGER #{trigger_name}
          BEFORE INSERT OR UPDATE OR DELETE ON #{quoted_table(table_name)}
          FOR EACH ROW
          EXECUTE FUNCTION #{function_name}();
        SQL
        execute(sql)

        say "Added write-block trigger to #{table_name}"
      end

      def remove_write_block_trigger(table_name, initial_table_name)
        trigger_name = "#{initial_table_name}_write_block_trigger"
        function_name = "#{initial_table_name}_write_block_function"

        execute "DROP TRIGGER IF EXISTS #{trigger_name} ON #{quoted_table(table_name)}"
        execute "DROP FUNCTION IF EXISTS #{function_name}()"
        say "Removed write-block trigger from #{table_name}"
      end

      def wait_for_active_transactions(table_name, timeout_seconds: 300, check_interval_seconds: 1)
        start_time = Time.current
        say "Waiting for active transactions on #{table_name} to complete..."

        loop do
          active_transactions_sql = <<~SQL
            SELECT COUNT(*) AS count
            FROM pg_stat_activity
            WHERE state IN ('active', 'idle in transaction')
              AND pid != pg_backend_pid()
              AND query NOT LIKE '%pg_stat_activity%'
              AND query NOT LIKE '%information_schema%'
              AND (
                query ILIKE '%#{table_name}%'
                OR query ILIKE '%LOCK TABLE #{table_name}%'
              )
          SQL

          active_count = execute(active_transactions_sql).first["count"].to_i
          if active_count.zero?
            say "No active transactions on #{table_name}"
            return true
          end

          elapsed = Time.current - start_time
          if elapsed > timeout_seconds
            raise "Timeout waiting for active transactions on #{table_name}. #{active_count} transactions still active."
          end

          say "Waiting... #{active_count} active transactions on #{table_name} (elapsed: #{elapsed.round}s)"
          sleep(check_interval_seconds)
        end
      end

      def sync_delta_data(batch_size: nil, source_table: nil, target_table: nil, swapped: false, sleep_seconds: 0)
        config = hot_switch_config
        batch_size = batch_size || config[:sync_batch_size] || PartitionGardener::MOVE_BATCH_SIZE
        source_table, target_table = resolve_sync_tables(source_table: source_table, target_table: target_table, swapped: swapped)
        partition_key_column = config[:partition_key_column]
        conflict_key = config[:conflict_key] || default_conflict_key(partition_key_column)
        derived_columns = config[:derived_columns] || {}
        stale_column = config[:sync_stale_column] || "updated_at"
        base_key = partition_key_column.to_s.split("::").first.strip
        current_partition_key_expression = config[:current_partition_key_expression] || "s.#{connection.quote_column_name(base_key)}"
        today = PartitionGardener.configuration.today
        start_date = DateCalendar.add_months(today, -3)
        end_date = DateCalendar.add_months(today, 3)
        start_date_sql = connection.quote(start_date)
        end_date_sql = connection.quote(end_date)

        say "Syncing delta data from #{source_table} to #{target_table}"

        current_columns = table_columns(source_table)
        partitioned_columns = table_columns(target_table)
        common_columns = current_columns & partitioned_columns
        insert_columns = (common_columns + derived_columns.keys) & partitioned_columns
        columns_str = insert_columns.map { |column| connection.quote_column_name(column) }.join(", ")
        inner_select_columns_str = insert_columns.map do |column|
          if derived_columns.key?(column)
            "#{derived_columns[column]} AS #{connection.quote_column_name(column)}"
          else
            "s.#{connection.quote_column_name(column)}"
          end
        end.join(", ")

        conflict_key_str = conflict_key.map { |column| connection.quote_column_name(column) }.join(", ")
        conflict_match = conflict_key.map { |column| "d.#{connection.quote_column_name(column)} = s.#{connection.quote_column_name(column)}" }.join(" AND ")
        update_columns = insert_columns - conflict_key
        update_clause = update_columns.map { |column| "#{connection.quote_column_name(column)} = EXCLUDED.#{connection.quote_column_name(column)}" }.join(", ")
        stale_check = if partitioned_columns.include?(stale_column)
          "d.#{connection.quote_column_name(stale_column)} >= s.#{connection.quote_column_name(stale_column)}"
        else
          "FALSE"
        end
        window_predicate = [
          "#{current_partition_key_expression} >= #{start_date_sql}",
          "AND #{current_partition_key_expression} < #{end_date_sql}",
          "AND NOT EXISTS (",
          "SELECT 1 FROM #{quoted_table(target_table)} d",
          "WHERE #{conflict_match}",
          "AND #{stale_check}",
          ")"
        ].join(" ")
        order_clause = conflict_key.map { |column| "s.#{connection.quote_column_name(column)}" }.join(", ")

        count_sql = <<~SQL
          SELECT COUNT(*) AS count
          FROM #{quoted_table(source_table)} s
          WHERE #{window_predicate}
        SQL

        records_to_sync = execute(count_sql).first["count"].to_i
        if records_to_sync.zero?
          say "No records to sync - tables are already in sync"
          return
        end

        say "Found #{records_to_sync} records to sync"

        conflict_update_sql = if update_columns.empty?
          <<~SQL.chomp
            ON CONFLICT (#{conflict_key_str}) DO NOTHING
          SQL
        elsif partitioned_columns.include?(stale_column)
          <<~SQL.chomp
            ON CONFLICT (#{conflict_key_str}) DO UPDATE SET
              #{update_clause}
            WHERE #{quoted_table(target_table)}.#{connection.quote_column_name(stale_column)} < EXCLUDED.#{connection.quote_column_name(stale_column)}
          SQL
        else
          <<~SQL.chomp
            ON CONFLICT (#{conflict_key_str}) DO UPDATE SET
              #{update_clause}
          SQL
        end

        synced_total = 0
        loop do
          sync_sql = <<~SQL
            INSERT INTO #{quoted_table(target_table)} (#{columns_str})
            SELECT #{columns_str}
            FROM (
              SELECT #{inner_select_columns_str}
              FROM #{quoted_table(source_table)} s
              WHERE #{window_predicate}
              ORDER BY #{order_clause}
              LIMIT #{batch_size.to_i}
            ) batch
            #{conflict_update_sql}
          SQL

          result = execute(sync_sql)
          synced_batch = result.cmd_tuples
          break if synced_batch.zero?

          synced_total += synced_batch
          sleep(sleep_seconds) if sleep_seconds.positive?
        end

        say "Synced #{synced_total} records"
      end

      def table_columns(table_name)
        sql = <<~SQL
          SELECT column_name
          FROM information_schema.columns
          WHERE table_schema = #{connection.quote(PartitionGardener.configuration.schema_name)}
            AND table_name = #{connection.quote(table_name)}
          ORDER BY ordinal_position
        SQL

        execute(sql).map { |row| row["column_name"] }
      end

      alias_method :get_table_columns, :table_columns

      def compare_table_counts
        config = hot_switch_config
        current_table = config[:current_table]
        partitioned_table = config[:partitioned_table]

        current_count = execute("SELECT COUNT(*) AS count FROM #{quoted_table(current_table)}").first["count"].to_i
        partitioned_count = execute("SELECT COUNT(*) AS count FROM #{quoted_table(partitioned_table)}").first["count"].to_i

        say "Count comparison:"
        say "  #{current_table}: #{current_count}"
        say "  #{partitioned_table}: #{partitioned_count}"
        say "  Difference: #{current_count - partitioned_count}"

        {
          current: current_count,
          partitioned: partitioned_count,
          difference: current_count - partitioned_count
        }
      end

      def fetch_partitions(table_name)
        sql = <<~SQL
          SELECT inhrelid::regclass AS child
          FROM pg_catalog.pg_inherits
          WHERE inhparent = #{connection.quote(table_name)}::regclass
        SQL
        execute(sql).map { |row| row["child"] }
      end

      def hot_switch_tables
        config = hot_switch_config
        current_table = config[:current_table]
        partitioned_table = config[:partitioned_table]
        old_table = "#{current_table}_old"

        return if connection.table_exists?(old_table)

        say "Performing hot switch: #{current_table} -> #{partitioned_table}"

        sequence_pairs = serial_sequence_pairs(current_table)

        transaction do
          apply_swap_lock_timeout!

          execute "ALTER TABLE #{quoted_table(current_table)} RENAME TO #{quoted_table(old_table)}"
          say "Renamed #{current_table} to #{old_table}"

          execute "ALTER TABLE #{quoted_table(partitioned_table)} RENAME TO #{quoted_table(current_table)}"
          say "Renamed #{partitioned_table} to #{current_table}"

          rename_partition_children!(current_table, partitioned_table, current_table)
          repoint_serial_sequences!(current_table, sequence_pairs)
          remove_write_block_trigger(old_table, current_table)
        end

        say "Hot switch completed successfully"
      end

      def hot_unswitch_tables
        config = hot_switch_config
        current_table = config[:current_table]
        partitioned_table = config[:partitioned_table]
        old_table = "#{current_table}_old"

        return unless connection.table_exists?(old_table)
        return if connection.table_exists?(partitioned_table)

        say "Performing hot unswitch: #{current_table} -> #{partitioned_table}"

        sequence_pairs = serial_sequence_pairs(current_table)

        transaction do
          apply_swap_lock_timeout!

          execute "ALTER TABLE #{quoted_table(current_table)} RENAME TO #{quoted_table(partitioned_table)}"
          say "Renamed #{current_table} to #{partitioned_table}"

          execute "ALTER TABLE #{quoted_table(old_table)} RENAME TO #{quoted_table(current_table)}"
          say "Renamed #{old_table} to #{current_table}"

          rename_partition_children!(partitioned_table, current_table, partitioned_table)
          repoint_serial_sequences!(current_table, sequence_pairs)
        end

        say "Hot unswitch completed successfully"
      end

      def serial_sequence_pairs(table_name)
        qualified_table = qualified_table_name(table_name)

        table_columns(table_name).filter_map do |column_name|
          sql = <<~SQL
            SELECT pg_get_serial_sequence(#{connection.quote(qualified_table)}, #{connection.quote(column_name)}) AS sequence_name
          SQL
          result = execute(sql).first
          sequence_name = result["sequence_name"]
          next if Blank.blank?(sequence_name)

          [column_name, sequence_name]
        end
      end

      private

      def hot_switch_config
        self.class::HOT_SWITCH_CONFIG
      end

      def resolve_partition_config(config)
        partition_config = config[:partition_config]
        return partition_config unless partition_config.is_a?(String) || partition_config.is_a?(Symbol)

        PartitionGardener::Registry.hot_switch_partition_config(partition_config.to_s)
      end

      def resolve_sync_tables(source_table:, target_table:, swapped:)
        config = hot_switch_config
        current_table = config[:current_table]
        partitioned_table = config[:partitioned_table]

        if swapped
          [source_table || "#{current_table}_old", target_table || current_table]
        else
          [source_table || current_table, target_table || partitioned_table]
        end
      end

      def swap_lock_timeout_setting
        config = hot_switch_config
        return config[:swap_lock_timeout] if config.key?(:swap_lock_timeout)

        DEFAULT_SWAP_LOCK_TIMEOUT
      end

      def apply_swap_lock_timeout!
        timeout = swap_lock_timeout_setting
        return if timeout.nil?

        execute "SET LOCAL lock_timeout = #{connection.quote(timeout)}"
      end

      def rename_partition_children!(parent_table, from_prefix, to_prefix)
        fetch_partitions(parent_table).each do |partition|
          partition_name = partition.to_s
          next if partition_name.include?(to_prefix)

          new_partition_name = partition_name.gsub(from_prefix, to_prefix)
          execute "ALTER TABLE #{partition} RENAME TO #{new_partition_name}"
          say "Renamed #{partition} to #{new_partition_name}"
        end
      end

      def repoint_serial_sequences!(table_name, sequence_pairs)
        sequence_pairs.each do |column_name, sequence_name|
          execute "ALTER SEQUENCE #{sequence_name} OWNED BY #{quoted_table(table_name)}.#{connection.quote_column_name(column_name)}"
          say "Repointed #{sequence_name} to #{table_name}.#{column_name}"
        end
      end

      def qualified_table_name(table_name)
        "#{PartitionGardener.configuration.schema_name}.#{table_name}"
      end

      def default_conflict_key(partition_key_column)
        base_key = partition_key_column.to_s.split("::").first.strip
        ["id", base_key]
      end

      def connection
        PartitionGardener.configuration.connection
      end

      def quoted_table(name)
        connection.quote_table_name(name)
      end
    end
  end
end

# Backward-compatible constant for migrations that include HotSwitchPartitionedTable.
HotSwitchPartitionedTable = PartitionGardener::Migration::HotSwitchConcern

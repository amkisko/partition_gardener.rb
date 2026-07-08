require "json"

module PartitionGardener
  class Executor
    def self.for_config(config, connection: Connection.connection)
      new(
        connection: connection,
        batch_size: config.fetch(:move_batch_size, MOVE_BATCH_SIZE)
      )
    end

    def initialize(connection: Connection.connection, batch_size: MOVE_BATCH_SIZE)
      @connection = connection
      @batch_size = batch_size
    end

    def attach_partition(table_name, partition_name, for_values_clause)
      sql = <<~SQL
        ALTER TABLE #{quoted_table(table_name)} ATTACH PARTITION #{quoted_table(partition_name)}
        FOR VALUES #{for_values_clause}
      SQL
      @connection.execute(sql)
    end

    def attach_default_partition(table_name, partition_name)
      sql = <<~SQL
        ALTER TABLE #{quoted_table(table_name)} ATTACH PARTITION #{quoted_table(partition_name)} DEFAULT
      SQL
      @connection.execute(sql)
    end

    def detach_partition(table_name, partition_name, concurrently: false)
      concurrently_keyword = concurrently ? "CONCURRENTLY " : ""
      sql = <<~SQL
        ALTER TABLE #{quoted_table(table_name)} DETACH PARTITION #{concurrently_keyword}#{quoted_table(partition_name)}
      SQL
      @connection.execute(sql)
    end

    def drop_table(table_name)
      sql = <<~SQL
        DROP TABLE IF EXISTS #{quoted_table(table_name)}
      SQL
      @connection.execute(sql)
    end

    def create_partition(table_name, partition_name, for_values_clause)
      sql = <<~SQL
        CREATE TABLE IF NOT EXISTS #{quoted_table(partition_name)} PARTITION OF #{quoted_table(table_name)}
        FOR VALUES #{for_values_clause}
      SQL
      @connection.execute(sql)
    end

    def ensure_detached_partition_table!(table_name, partition_name, conflict_key:)
      sql = <<~SQL
        CREATE TABLE IF NOT EXISTS #{quoted_table(partition_name)} (
          LIKE #{quoted_table(table_name)} INCLUDING ALL
        )
      SQL
      @connection.execute(sql)

      conflict_columns = conflict_key.map { |column| @connection.quote_column_name(column) }.join(", ")
      sql = <<~SQL
        CREATE UNIQUE INDEX IF NOT EXISTS #{@connection.quote_column_name("#{partition_name}_conflict_key_idx")}
        ON #{quoted_table(partition_name)} (#{conflict_columns})
      SQL
      @connection.execute(sql)
    end

    def move_all_rows_between_partitions!(source_partition_name, destination_partition_name, conflict_key, cursor_columns: conflict_key)
      move_rows_between_partitions!(
        source_partition_name: source_partition_name,
        destination_partition_name: destination_partition_name,
        where_condition: nil,
        conflict_key: conflict_key,
        cursor_columns: cursor_columns
      )
    end

    def drain_rows_between_partitions!(source_partition_name, destination_partition_name, where_condition, conflict_key, cursor_columns: conflict_key)
      move_rows_between_partitions!(
        source_partition_name: source_partition_name,
        destination_partition_name: destination_partition_name,
        where_condition: where_condition,
        conflict_key: conflict_key,
        cursor_columns: cursor_columns
      )
    end

    def move_all_rows_to_parent!(table_name, source_partition_name, conflict_key, cursor_columns: conflict_key)
      ensure_parent_conflict_index!(table_name, conflict_key)
      move_rows_with_keyset!(
        source_partition_name: source_partition_name,
        insert_target: quoted_table(table_name),
        where_condition: nil,
        conflict_key: conflict_key,
        cursor_columns: cursor_columns
      )
    end

    def move_rows_to_parent_partition!(
      table_name:,
      source_partition_name:,
      where_condition:,
      destination_partition_name:,
      conflict_key:,
      record_count:,
      cursor_columns: conflict_key
    )
      ensure_parent_conflict_index!(table_name, conflict_key)

      PartitionGardener.configuration.notify(
        "[PartitionGardener] Moving #{record_count} rows from #{source_partition_name} to #{destination_partition_name}",
        context: {
          table_name: table_name,
          source_partition_name: source_partition_name,
          destination_partition_name: destination_partition_name,
          record_count: record_count
        }
      )

      moved_rows = move_rows_with_keyset!(
        source_partition_name: source_partition_name,
        insert_target: quoted_table(table_name),
        where_condition: where_condition,
        conflict_key: conflict_key,
        cursor_columns: cursor_columns
      )

      PartitionGardener.configuration.notify(
        "[PartitionGardener] Moved #{moved_rows} rows from #{source_partition_name} to #{destination_partition_name}",
        context: {
          table_name: table_name,
          source_partition_name: source_partition_name,
          destination_partition_name: destination_partition_name,
          moved_rows: moved_rows
        }
      )
    end

    private

    def quoted_table(name)
      @connection.quote_table_name(name)
    end

    def quoted_conflict_key(conflict_key)
      conflict_key.map { |column| @connection.quote_column_name(column) }.join(", ")
    end

    def move_rows_between_partitions!(source_partition_name:, destination_partition_name:, where_condition:, conflict_key:, cursor_columns:)
      move_rows_with_keyset!(
        source_partition_name: source_partition_name,
        insert_target: quoted_table(destination_partition_name),
        where_condition: where_condition,
        conflict_key: conflict_key,
        cursor_columns: cursor_columns
      )
    end

    def move_rows_with_keyset!(source_partition_name:, insert_target:, where_condition:, conflict_key:, cursor_columns:)
      moved_rows = 0
      last_cursor = nil

      loop do
        batch_result = execute_move_batch(
          source_partition_name: source_partition_name,
          insert_target: insert_target,
          where_condition: where_condition,
          conflict_key: conflict_key,
          cursor_columns: cursor_columns,
          last_cursor: last_cursor
        )

        moved_rows += batch_result[:deleted]
        last_cursor = batch_result[:last_cursor]
        if batch_result[:deleted].zero?
          if batch_result[:batch_size].positive?
            raise UnmovedRowsRemaining.new(
              source_partition_name: source_partition_name,
              batch_size: batch_result[:batch_size],
              last_cursor: last_cursor
            )
          end

          break
        end
        break if batch_result[:batch_size] < @batch_size
      end

      record_rows_moved!(moved_rows)
      moved_rows
    end

    def record_rows_moved!(count)
      PartitionGardener.configuration.current_run_metrics&.add_rows(count)
    end

    def execute_move_batch(source_partition_name:, insert_target:, where_condition:, conflict_key:, cursor_columns:, last_cursor:)
      order_sql = cursor_columns.map { |column| @connection.quote_column_name(column) }.join(", ")
      conflict_key_sql = quoted_conflict_key(conflict_key)
      cursor_columns_sql = order_sql
      inserted_not_exists_sql = column_match_sql("inserted_rows", "batch_rows", cursor_columns)
      target_exists_sql = column_match_sql("target_rows", "batch_rows", conflict_key)
      removable_match_sql = column_match_sql("source_rows", "removable_rows", cursor_columns)
      returning_sql = cursor_columns.map { |column| "source_rows.#{@connection.quote_column_name(column)}" }.join(", ")

      where_parts = []
      where_parts << where_condition if where_condition
      keyset_sql = keyset_after_clause(cursor_columns, last_cursor)
      where_parts << keyset_sql if keyset_sql
      where_clause = where_parts.any? ? "WHERE #{where_parts.join(" AND ")}" : ""

      sql = <<~SQL
        WITH batch_rows AS (
          SELECT *
          FROM #{quoted_table(source_partition_name)}
          #{where_clause}
          ORDER BY #{order_sql}
          LIMIT #{@batch_size}
        ),
        inserted_rows AS (
          INSERT INTO #{insert_target}
          SELECT * FROM batch_rows
          ON CONFLICT (#{conflict_key_sql}) DO NOTHING
          RETURNING #{cursor_columns_sql}
        ),
        duplicates_at_target AS (
          SELECT #{cursor_columns_sql}
          FROM batch_rows
          WHERE NOT EXISTS (
            SELECT 1
            FROM inserted_rows
            WHERE #{inserted_not_exists_sql}
          )
          AND EXISTS (
            SELECT 1
            FROM #{insert_target} AS target_rows
            WHERE #{target_exists_sql}
          )
        ),
        removable_rows AS (
          SELECT #{cursor_columns_sql} FROM inserted_rows
          UNION
          SELECT #{cursor_columns_sql} FROM duplicates_at_target
        ),
        deleted_rows AS (
          DELETE FROM #{quoted_table(source_partition_name)} AS source_rows
          USING removable_rows
          WHERE #{removable_match_sql}
          RETURNING #{returning_sql}
        )
        SELECT
          (SELECT COUNT(*)::int FROM deleted_rows) AS deleted,
          (SELECT COUNT(*)::int FROM batch_rows) AS batch_size,
          (
            SELECT row_to_json(last_row)
            FROM (
              SELECT #{order_sql}
              FROM batch_rows
              ORDER BY #{order_sql} DESC
              LIMIT 1
            ) AS last_row
          ) AS last_cursor
      SQL

      row = @connection.execute(sql).first
      deleted = row["deleted"].to_i
      batch_size = row["batch_size"].to_i
      last_cursor_values = parse_last_cursor(row["last_cursor"], cursor_columns)

      {
        deleted: deleted,
        batch_size: batch_size,
        last_cursor: last_cursor_values
      }
    end

    def column_match_sql(left_alias, right_alias, columns)
      columns.map do |column|
        quoted_column = @connection.quote_column_name(column)
        "#{left_alias}.#{quoted_column} = #{right_alias}.#{quoted_column}"
      end.join(" AND ")
    end

    def keyset_after_clause(columns, last_values)
      return nil if last_values.nil?

      column_sql = columns.map { |column| @connection.quote_column_name(column) }.join(", ")
      value_sql = last_values.map { |value| @connection.quote(value) }.join(", ")
      "(#{column_sql}) > (#{value_sql})"
    end

    def parse_last_cursor(last_cursor_json, cursor_columns)
      return nil if last_cursor_json.nil?

      payload = last_cursor_json.is_a?(String) ? JSON.parse(last_cursor_json) : last_cursor_json
      cursor_columns.map { |column| payload[column] || payload[column.to_s] }
    end

    def ensure_parent_conflict_index!(table_name, conflict_key)
      return if Connection.unique_index_covers?(table_name, conflict_key)

      index_name = "#{table_name}_#{conflict_key.join("_")}_maintenance_conflict_idx"
      columns_sql = conflict_key.map { |column| @connection.quote_column_name(column) }.join(", ")
      sql = <<~SQL
        CREATE UNIQUE INDEX IF NOT EXISTS #{@connection.quote_column_name(index_name)}
        ON #{quoted_table(table_name)} (#{columns_sql})
      SQL
      @connection.execute(sql)

      return if Connection.unique_index_covers?(table_name, conflict_key)

      raise MissingConflictIndex,
        "#{table_name} needs a unique index on (#{conflict_key.join(", ")}) including the partition key for row moves"
    rescue => error
      raise if error.is_a?(MissingConflictIndex)

      raise MissingConflictIndex,
        "#{table_name} needs a unique index on (#{conflict_key.join(", ")}) including the partition key for row moves: #{error.message}"
    end
  end
end

module PartitionGardener
  class SqlRunRecordStore
    TABLE_NAME = "partition_gardener_run_records"

    def initialize
      @schema_mutex = Mutex.new
      @schema_ready = false
    end

    def load(table_name)
      ensure_schema!
      sql = load_sql(table_name)
      row = connection.execute(sql).first

      return unless row

      {
        table_name: row["table_name"],
        phase: row["phase"],
        plan_signature: row["plan_signature"],
        staging_row_count: row["staging_row_count"].to_i
      }
    end

    def save(table_name, attributes)
      ensure_schema!
      sql = save_sql(table_name, attributes)
      connection.execute(sql)
    end

    def clear(table_name)
      ensure_schema!
      sql = clear_sql(table_name)
      connection.execute(sql)
    end

    def ensure_schema!
      return if @schema_ready

      @schema_mutex.synchronize do
        return if @schema_ready

        connection.execute(create_table_sql)
        @schema_ready = true
      end
    end

    private

    def connection
      PartitionGardener.configuration.connection
    end

    def quoted_table(name)
      connection.quote_table_name(name)
    end

    def load_sql(table_name)
      <<~SQL
        SELECT table_name, phase, plan_signature, staging_row_count
        FROM #{quoted_table(TABLE_NAME)}
        WHERE table_name = #{connection.quote(table_name)}
      SQL
    end

    def save_sql(table_name, attributes)
      <<~SQL
        INSERT INTO #{quoted_table(TABLE_NAME)} (
          table_name, phase, plan_signature, staging_row_count, updated_at
        ) VALUES (
          #{connection.quote(table_name)},
          #{connection.quote(attributes.fetch(:phase))},
          #{connection.quote(attributes.fetch(:plan_signature))},
          #{attributes.fetch(:staging_row_count, 0).to_i},
          NOW()
        )
        ON CONFLICT (table_name) DO UPDATE SET
          phase = EXCLUDED.phase,
          plan_signature = EXCLUDED.plan_signature,
          staging_row_count = EXCLUDED.staging_row_count,
          updated_at = NOW()
      SQL
    end

    def clear_sql(table_name)
      <<~SQL
        DELETE FROM #{quoted_table(TABLE_NAME)}
        WHERE table_name = #{connection.quote(table_name)}
      SQL
    end

    def create_table_sql
      <<~SQL
        CREATE TABLE IF NOT EXISTS #{quoted_table(TABLE_NAME)} (
          table_name text PRIMARY KEY,
          phase text NOT NULL,
          plan_signature text NOT NULL,
          staging_row_count integer NOT NULL DEFAULT 0,
          updated_at timestamptz NOT NULL DEFAULT NOW()
        )
      SQL
    end
  end

  ActiveRecordRunRecordStore = SqlRunRecordStore
end

require "pg"

module PartitionGardener
  class PgConnection
    class Result
      include Enumerable

      def initialize(pg_result)
        @pg_result = pg_result
      end

      def first
        return nil if @pg_result.ntuples.zero?

        @pg_result[0]
      end

      def to_a
        @pg_result.to_a
      end

      def cmd_tuples
        @pg_result.cmd_tuples
      end

      def each
        return enum_for(:each) unless block_given?

        @pg_result.each { |row| yield row }
      end
    end

    def self.connect(database_url)
      new(PG.connect(database_url))
    end

    def initialize(raw_connection)
      @raw_connection = raw_connection
    end

    def quote(value)
      case value
      when nil
        "NULL"
      when true
        "TRUE"
      when false
        "FALSE"
      when Numeric
        value.to_s
      when Date, Time
        "'#{@raw_connection.escape_string(value.iso8601)}'"
      else
        "'#{@raw_connection.escape_string(value.to_s)}'"
      end
    end

    def quote_table_name(name)
      @raw_connection.quote_ident(name.to_s)
    end

    def quote_column_name(name)
      quote_table_name(name)
    end

    def execute(sql)
      Result.new(@raw_connection.exec(sql))
    end

    def transaction
      @raw_connection.exec("BEGIN")
      yield
      @raw_connection.exec("COMMIT")
    rescue
      @raw_connection.exec("ROLLBACK")
      raise
    end

    def table_exists?(table_name)
      sql = <<~SQL
        SELECT EXISTS (
          SELECT 1
          FROM pg_catalog.pg_class AS relation
          JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = relation.relnamespace
          WHERE namespace.nspname = ANY (current_schemas(false))
            AND relation.relname = $1
            AND relation.relkind IN ('r', 'p')
        ) AS exists
      SQL
      result = @raw_connection.exec_params(sql, [table_name.to_s])
      result.getvalue(0, 0) == "t"
    end
  end
end

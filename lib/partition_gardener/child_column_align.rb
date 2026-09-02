module PartitionGardener
  class ChildColumnAlign
    Column = Data.define(
      :name,
      :type,
      :not_null,
      :default_expression,
      :collation_schema,
      :collation_name
    )

    def self.lagging_child_warnings(parent_table, connection: Connection.connection, candidate_table: nil)
      new(connection: connection).lagging_child_warnings(parent_table, candidate_table: candidate_table)
    end

    def initialize(connection: Connection.connection)
      @connection = connection
    end

    def align!(parent_table, child_table)
      missing = missing_ordinary_columns(parent_table, child_table)
      add_columns!(child_table, missing) if missing.any?
    end

    def lagging_child_warnings(parent_table, candidate_table: nil)
      child_tables = unattached_child_tables(parent_table)
      child_tables.select!(&candidate_table) if candidate_table
      columns_by_table = ordinary_columns_by_table([parent_table, *child_tables])
      parent_columns = columns_by_table.fetch(parent_table, [])

      child_tables.filter_map do |child_table|
        missing = missing_columns(parent_columns, columns_by_table.fetch(child_table, []))
        next if missing.empty?

        missing_columns_warning(child_table, parent_table, missing)
      end
    end

    def missing_ordinary_columns(parent_table, child_table)
      columns_by_table = ordinary_columns_by_table([parent_table, child_table])
      missing_columns(
        columns_by_table.fetch(parent_table, []),
        columns_by_table.fetch(child_table, [])
      )
    end

    private

    def add_columns!(child_table, columns)
      actions = columns.map { |column| add_column_action(column) }.join(",\n  ")
      @connection.execute(<<~SQL)
        ALTER TABLE #{quoted_table(child_table)}
          #{actions}
      SQL
    end

    def add_column_action(column)
      clauses = ["ADD COLUMN #{quoted_column(column.name)} #{column.type}"]
      if column.collation_name
        clauses << "COLLATE #{quoted_column(column.collation_schema)}.#{quoted_column(column.collation_name)}"
      end
      clauses << "DEFAULT #{column.default_expression}" if usable_default?(column.default_expression)
      clauses << "NOT NULL" if column.not_null
      clauses.join(" ")
    end

    def ordinary_columns_by_table(table_names)
      names = table_names.uniq
      quoted_names = names.map { |table_name| @connection.quote(table_name) }.join(", ")
      sql = <<~SQL
        SELECT
          table_class.relname AS table_name,
          attribute.attname AS name,
          pg_catalog.format_type(attribute.atttypid, attribute.atttypmod) AS type,
          attribute.attnotnull AS not_null,
          pg_get_expr(column_default.adbin, column_default.adrelid) AS default_expression,
          attribute.attidentity AS identity,
          attribute.attgenerated AS generated,
          collation_namespace.nspname AS collation_schema,
          column_collation.collname AS collation_name
        FROM pg_attribute attribute
        LEFT JOIN pg_attrdef column_default
          ON column_default.adrelid = attribute.attrelid
          AND column_default.adnum = attribute.attnum
        JOIN pg_class table_class ON table_class.oid = attribute.attrelid
        JOIN pg_namespace table_namespace ON table_namespace.oid = table_class.relnamespace
        JOIN pg_type attribute_type ON attribute_type.oid = attribute.atttypid
        LEFT JOIN pg_collation column_collation
          ON column_collation.oid = attribute.attcollation
          AND attribute.attcollation <> attribute_type.typcollation
        LEFT JOIN pg_namespace collation_namespace
          ON collation_namespace.oid = column_collation.collnamespace
        WHERE table_namespace.nspname = #{@connection.quote(schema_name)}
          AND table_class.relname IN (#{quoted_names})
          AND attribute.attnum > 0
          AND NOT attribute.attisdropped
        ORDER BY table_class.relname, attribute.attnum
      SQL
      @connection.execute(sql).each_with_object({}) do |row, columns_by_table|
        next if Blank.present?(row["identity"]) || Blank.present?(row["generated"])

        column = Column.new(
          name: row["name"],
          type: row["type"],
          not_null: flag?(row["not_null"]),
          default_expression: row["default_expression"],
          collation_schema: row["collation_schema"],
          collation_name: row["collation_name"]
        )
        (columns_by_table[row["table_name"]] ||= []) << column
      end
    end

    def missing_columns(parent_columns, child_columns)
      child_names = child_columns.to_h { |column| [column.name, true] }
      parent_columns.reject { |column| child_names.key?(column.name) }
    end

    def unattached_child_tables(parent_table)
      sql = <<~SQL
        SELECT child.relname
        FROM pg_class child
        JOIN pg_namespace child_namespace ON child_namespace.oid = child.relnamespace
        WHERE child_namespace.nspname = #{@connection.quote(schema_name)}
          AND child.relkind = 'r'
          AND starts_with(child.relname, #{@connection.quote("#{parent_table}_")})
          AND NOT EXISTS (
            SELECT 1
            FROM pg_inherits inheritance
            WHERE inheritance.inhrelid = child.oid
          )
        ORDER BY child.relname
      SQL
      @connection.execute(sql).map { |row| row["relname"] }
    end

    def missing_columns_warning(child_table, parent_table, missing)
      names = missing.map(&:name).join(", ")
      noun = (missing.size == 1) ? "column" : "columns"
      "child #{child_table} is missing #{noun} #{names} from parent #{parent_table}"
    end

    def usable_default?(expression)
      return false if Blank.blank?(expression)

      !expression.strip.match?(/\ANULL(::[\w.]+)?\z/i)
    end

    def flag?(value)
      value == true || value.to_s == "t" || value.to_s == "true"
    end

    def quoted_table(name)
      @connection.quote_table_name(name)
    end

    def quoted_column(name)
      @connection.quote_column_name(name)
    end

    def schema_name
      PartitionGardener.configuration.schema_name
    end
  end
end

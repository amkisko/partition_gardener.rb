module PartitionGardener
  class ChildColumnAlign
    Column = Data.define(:name, :type, :not_null, :default_expression)

    def self.lagging_child_warnings(parent_table, connection: Connection.connection)
      new(connection: connection).lagging_child_warnings(parent_table)
    end

    def initialize(connection: Connection.connection)
      @connection = connection
    end

    def align!(parent_table, child_table)
      missing_ordinary_columns(parent_table, child_table).each do |column|
        add_column!(child_table, column)
      end
    end

    def lagging_child_warnings(parent_table)
      unattached_child_tables(parent_table).filter_map do |child_table|
        missing = missing_ordinary_columns(parent_table, child_table)
        next if missing.empty?

        missing_columns_warning(child_table, parent_table, missing)
      end
    end

    def missing_ordinary_columns(parent_table, child_table)
      child_names = ordinary_columns(child_table).map(&:name)
      ordinary_columns(parent_table).reject { |column| child_names.include?(column.name) }
    end

    private

    def add_column!(child_table, column)
      clauses = [
        "ALTER TABLE #{quoted_table(child_table)} ADD COLUMN #{quoted_column(column.name)} #{column.type}"
      ]
      clauses << "DEFAULT #{column.default_expression}" if usable_default?(column.default_expression)
      @connection.execute(clauses.join(" "))

      return unless column.not_null
      return unless usable_default?(column.default_expression) || child_empty?(child_table)

      @connection.execute(<<~SQL)
        ALTER TABLE #{quoted_table(child_table)} ALTER COLUMN #{quoted_column(column.name)} SET NOT NULL
      SQL
    end

    def ordinary_columns(table_name)
      sql = <<~SQL
        SELECT
          attribute.attname AS name,
          pg_catalog.format_type(attribute.atttypid, attribute.atttypmod) AS type,
          attribute.attnotnull AS not_null,
          pg_get_expr(column_default.adbin, column_default.adrelid) AS default_expression,
          attribute.attidentity AS identity,
          attribute.attgenerated AS generated
        FROM pg_attribute attribute
        LEFT JOIN pg_attrdef column_default
          ON column_default.adrelid = attribute.attrelid
          AND column_default.adnum = attribute.attnum
        JOIN pg_class table_class ON table_class.oid = attribute.attrelid
        JOIN pg_namespace table_namespace ON table_namespace.oid = table_class.relnamespace
        WHERE table_namespace.nspname = #{@connection.quote(schema_name)}
          AND table_class.relname = #{@connection.quote(table_name)}
          AND attribute.attnum > 0
          AND NOT attribute.attisdropped
        ORDER BY attribute.attnum
      SQL
      @connection.execute(sql).filter_map do |row|
        next if Blank.present?(row["identity"]) || Blank.present?(row["generated"])

        Column.new(
          name: row["name"],
          type: row["type"],
          not_null: flag?(row["not_null"]),
          default_expression: row["default_expression"]
        )
      end
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

    def child_empty?(child_table)
      sql = <<~SQL
        SELECT COUNT(*) AS count
        FROM #{quoted_table(child_table)}
      SQL
      @connection.execute(sql).first["count"].to_i.zero?
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

module PartitionGardener
  module Connection
    module_function

    def connection
      PartitionGardener.configuration.connection
    end

    def schema_name
      PartitionGardener.configuration.schema_name
    end

    def quoted_table(name)
      connection.quote_table_name(name)
    end

    def table_is_partitioned?(table_name)
      return false unless connection.table_exists?(table_name)

      sql = <<~SQL
        SELECT COUNT(*) AS count
        FROM pg_partitioned_table pt
        JOIN pg_class c ON c.oid = pt.partrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = #{connection.quote(schema_name)}
          AND c.relname = #{connection.quote(table_name)}
      SQL
      connection.execute(sql).first["count"].to_i.positive?
    end

    def partition_exists?(partition_name)
      connection.table_exists?(partition_name)
    end

    def partition_attached?(table_name, partition_name)
      sql = <<~SQL
        SELECT COUNT(*) AS count
        FROM pg_catalog.pg_inherits i
        JOIN pg_class parent ON parent.oid = i.inhparent
        JOIN pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace
        JOIN pg_class child ON child.oid = i.inhrelid
        JOIN pg_namespace child_ns ON child_ns.oid = child.relnamespace
        WHERE parent_ns.nspname = #{connection.quote(schema_name)}
          AND child_ns.nspname = #{connection.quote(schema_name)}
          AND parent.relname = #{connection.quote(table_name)}
          AND child.relname = #{connection.quote(partition_name)}
      SQL

      connection.execute(sql).first["count"].to_i.positive?
    end

    def current_partition_lower_bound(table_name, partition_name)
      sql = <<~SQL
        SELECT pg_get_expr(child.relpartbound, child.oid) AS bound_expression
        FROM pg_catalog.pg_inherits inheritance
        JOIN pg_class parent ON parent.oid = inheritance.inhparent
        JOIN pg_namespace parent_namespace ON parent_namespace.oid = parent.relnamespace
        JOIN pg_class child ON child.oid = inheritance.inhrelid
        JOIN pg_namespace child_namespace ON child_namespace.oid = child.relnamespace
        WHERE parent_namespace.nspname = #{connection.quote(schema_name)}
          AND child_namespace.nspname = #{connection.quote(schema_name)}
          AND parent.relname = #{connection.quote(table_name)}
          AND child.relname = #{connection.quote(partition_name)}
      SQL

      bound_expression = connection.execute(sql).first&.fetch("bound_expression", nil)
      return if Blank.blank?(bound_expression)

      match = bound_expression.match(/FROM \('([^']+)'\)/)
      match ? Date.parse(match[1]) : nil
    end

    def count_rows_in_partition_table(partition_name)
      sql = <<~SQL
        SELECT COUNT(*) AS count
        FROM #{quoted_table(partition_name)}
      SQL
      connection.execute(sql).first["count"].to_i
    end

    def count_rows_in_partition(partition_name, where_condition)
      sql = <<~SQL
        SELECT COUNT(*) AS count
        FROM #{quoted_table(partition_name)}
        WHERE #{where_condition}
      SQL
      connection.execute(sql).first["count"].to_i
    end

    def attached_partitions(table_name)
      attached_partitions_cache[table_name] ||= fetch_attached_partitions(table_name)
    end

    def clear_attached_partitions_cache!
      Thread.current[:partition_gardener_attached_partitions] = nil
    end

    def fetch_attached_partitions(table_name)
      sql = <<~SQL
        SELECT child.relname AS partition_name,
               pg_get_expr(child.relpartbound, child.oid) AS bound_expression
        FROM pg_catalog.pg_inherits inheritance
        JOIN pg_class parent ON parent.oid = inheritance.inhparent
        JOIN pg_namespace parent_namespace ON parent_namespace.oid = parent.relnamespace
        JOIN pg_class child ON child.oid = inheritance.inhrelid
        JOIN pg_namespace child_namespace ON child_namespace.oid = child.relnamespace
        WHERE parent_namespace.nspname = #{connection.quote(schema_name)}
          AND child_namespace.nspname = #{connection.quote(schema_name)}
          AND parent.relname = #{connection.quote(table_name)}
        ORDER BY child.relname
      SQL

      connection.execute(sql).filter_map do |row|
        parse_attached_partition(row["partition_name"], row["bound_expression"])
      end
    end

    def attached_partitions_cache
      Thread.current[:partition_gardener_attached_partitions] ||= {}
    end

    private :attached_partitions_cache, :fetch_attached_partitions

    def parse_attached_partition(partition_name, bound_expression)
      return if Blank.blank?(bound_expression)

      if bound_expression == "DEFAULT"
        return AttachedPartition.new(
          name: partition_name,
          range_start: nil,
          range_end: nil,
          default: true,
          list_values: nil
        )
      end

      hash_match = bound_expression.match(/modulus (\d+), remainder (\d+)/)
      if hash_match
        return AttachedPartition.new(
          name: partition_name,
          range_start: {modulus: hash_match[1].to_i, remainder: hash_match[2].to_i},
          range_end: nil,
          default: false,
          list_values: nil
        )
      end

      list_match = bound_expression.match(/^IN \((.+)\)$/)
      if list_match
        values = list_match[1].split(",").map { |value| parse_list_value(value.strip) }
        return AttachedPartition.new(
          name: partition_name,
          range_start: values.first,
          range_end: nil,
          default: false,
          list_values: values
        )
      end

      from_match = bound_expression.match(/FROM \('([^']+)'\)/) || bound_expression.match(/FROM \((\d+)\)/)
      to_match = bound_expression.match(/TO \('([^']+)'\)/) || bound_expression.match(/TO \((\d+)\)/)
      range_end = if bound_expression.include?("MAXVALUE")
        :max
      elsif to_match
        parse_bound_value(to_match[1])
      end

      AttachedPartition.new(
        name: partition_name,
        range_start: from_match ? parse_bound_value(from_match[1]) : nil,
        range_end: range_end,
        default: false,
        list_values: nil
      )
    end

    def parse_list_value(value)
      return nil if value.upcase == "NULL"

      value.delete_prefix("'").delete_suffix("'")
    end

    def parse_bound_value(value)
      return Date.parse(value) if value.include?("-")

      value.to_i
    end

    AttachedPartition = Data.define(:name, :range_start, :range_end, :default, :list_values) do
      def signature
        [name, range_start, range_end, default, list_values]
      end
    end

    def get_distinct_partition_identifiers(partition_name, partition_key_column, extract_partition_identifier)
      if partition_key_column.include?("::")
        base_column = partition_key_column.split("::").first.strip
        sql = <<~SQL
          SELECT DISTINCT #{partition_key_column} AS partition_key_value
          FROM #{quoted_table(partition_name)}
          WHERE #{connection.quote_column_name(base_column)} IS NOT NULL
          ORDER BY #{partition_key_column}
        SQL
      else
        sql = <<~SQL
          SELECT DISTINCT #{connection.quote_column_name(partition_key_column)} AS partition_key_value
          FROM #{quoted_table(partition_name)}
          WHERE #{connection.quote_column_name(partition_key_column)} IS NOT NULL
          ORDER BY #{connection.quote_column_name(partition_key_column)}
        SQL
      end

      connection.execute(sql).to_a.filter_map do |row|
        value = row["partition_key_value"]
        extract_partition_identifier.call(value) if Blank.present?(value)
      end.uniq
    end

    def unique_index_column_sets(table_name)
      sql = <<~SQL
        SELECT i.indisprimary AS is_primary,
               array_agg(a.attname ORDER BY key_ord.ordinality) AS column_names
        FROM pg_index i
        JOIN pg_class table_class ON table_class.oid = i.indrelid
        JOIN pg_namespace table_namespace ON table_namespace.oid = table_class.relnamespace
        JOIN LATERAL unnest(i.indkey) WITH ORDINALITY AS key_ord(attnum, ordinality) ON true
        JOIN pg_attribute a ON a.attrelid = table_class.oid AND a.attnum = key_ord.attnum
        WHERE table_namespace.nspname = #{connection.quote(schema_name)}
          AND table_class.relname = #{connection.quote(table_name)}
          AND (i.indisunique OR i.indisprimary)
        GROUP BY i.indexrelid, i.indisprimary
      SQL

      connection.execute(sql).map do |row|
        columns = row["column_names"]
        columns = columns.gsub(/[{}]/, "").split(",") if columns.is_a?(String)
        columns
      end
    end

    def unique_index_covers?(table_name, conflict_key)
      conflict_columns = conflict_key.map(&:to_s)
      unique_index_column_sets(table_name).any? do |index_columns|
        index_columns.first(conflict_columns.length) == conflict_columns
      end
    end

    def partman_parent_configured?(table_name)
      qualified_name = "#{schema_name}.#{table_name}"
      sql = <<~SQL
        SELECT 1
        FROM partman.part_config
        WHERE parent_table = #{connection.quote(qualified_name)}
        LIMIT 1
      SQL

      connection.execute(sql).any?
    end
  end
end

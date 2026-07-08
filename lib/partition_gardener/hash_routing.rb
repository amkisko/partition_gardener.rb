module PartitionGardener
  module HashRouting
    module_function

    def collect_bucket_counts(config)
      table_name = config[:table_name]
      modulus = config.fetch(:hash_modulus, Strategy::HashBranches::DEFAULT_MODULUS)
      bucket_counts = Hash.new(0)

      Connection.attached_partitions(table_name).each do |partition|
        next if partition.default

        remainder = remainder_from_partition(partition, table_name)
        next if remainder.nil?

        bucket_counts[remainder] += Connection.count_rows_in_partition_table(partition.name)
      end

      default_name = Naming.default_partition_name(table_name)
      if Connection.partition_exists?(default_name) && Connection.partition_attached?(table_name, default_name)
        counts_in_default(default_name, config[:partition_key_column], modulus).each do |remainder, count|
          bucket_counts[remainder] += count
        end
      end

      bucket_counts
    end

    def remainder_from_partition(partition, table_name)
      if partition.range_start.is_a?(Hash) && partition.range_start.key?(:remainder)
        return partition.range_start[:remainder]
      end

      match = partition.name.match(/^#{Regexp.escape(table_name)}_[ha]_(\d+)$/)
      return match[1].to_i if match

      nil
    end

    def counts_in_default(partition_name, partition_key_column, modulus)
      connection = Connection.connection
      column = connection.quote_column_name(partition_key_column)
      remainder_sql = remainder_sql_expression(column, modulus, connection)

      sql = <<~SQL
        SELECT #{remainder_sql} AS remainder,
               COUNT(*)::int AS row_count
        FROM #{Connection.quoted_table(partition_name)}
        GROUP BY 1
      SQL

      connection.execute(sql).each_with_object({}) do |row, counts|
        counts[row["remainder"].to_i] = row["row_count"].to_i
      end
    end

    def remainder_sql_expression(quoted_column, modulus, connection)
      if integer_column?(quoted_column)
        "mod(abs(hashint8extended(#{quoted_column}::bigint, 0)), #{modulus})"
      else
        "mod(abs(hashtextextended(#{quoted_column}::text, 0)), #{modulus})"
      end
    end

    def integer_column?(quoted_column)
      normalized = quoted_column.delete('"').downcase
      normalized == "id" || normalized.end_with?("_id")
    end
  end
end

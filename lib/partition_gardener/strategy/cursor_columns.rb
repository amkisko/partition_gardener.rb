module PartitionGardener
  module Strategy
    module CursorColumns
      def cursor_columns
        base_key = partition_key_base
        conflict_columns = @config[:conflict_key] || [base_key, "id"]
        ([base_key] + conflict_columns).uniq
      end

      def partition_key_base
        column = @config[:partition_key_column]
        return column.to_s if column.nil?

        column.to_s.split("::").first.strip
      end
    end
  end
end

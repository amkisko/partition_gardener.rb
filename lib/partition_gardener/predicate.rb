module PartitionGardener
  module Predicate
    COLUMN_PATTERN = /\A[a-z_][a-z0-9_]*\z/i
    OPERATORS = %w[eq ne is_null is_not_null].freeze

    module_function

    def render(predicate, connection: nil)
      connection ||= Connection.connection
      predicate = predicate.transform_keys(&:to_sym)
      column = predicate.fetch(:column)
      operator = predicate.fetch(:operator).to_s

      validate_column!(column)
      validate_operator!(operator)

      quoted_column = connection.quote_column_name(column)

      case operator
      when "eq"
        "#{quoted_column} = #{connection.quote(predicate.fetch(:value))}"
      when "ne"
        "#{quoted_column} <> #{connection.quote(predicate.fetch(:value))}"
      when "is_null"
        "#{quoted_column} IS NULL"
      when "is_not_null"
        "#{quoted_column} IS NOT NULL"
      end
    end

    def normalize_branch!(branch, discriminator_column: nil, connection: nil)
      entry = branch.transform_keys(&:to_sym)
      entry = entry.dup

      if entry[:predicate]
        entry[:where_condition] = render(entry[:predicate], connection: connection)
        entry.delete(:predicate)
      elsif entry[:where_condition]
        entry[:where_condition] = entry[:where_condition].to_s
      elsif (column = entry[:discriminator_column] || discriminator_column) && entry.key?(:value)
        entry[:where_condition] = render(
          {column: column, operator: "eq", value: entry[:value]},
          connection: connection
        )
      else
        name = entry[:name] || "?"
        raise ArgumentError,
          "branch #{name.inspect} needs predicate, where_condition, or value with discriminator_column"
      end

      entry
    end

    def normalize_branches!(branches, discriminator_column: nil, connection: nil)
      branches.map do |branch|
        normalize_branch!(branch, discriminator_column: discriminator_column, connection: connection)
      end
    end

    def list_branch_entries(branches, discriminator_column: nil, connection: nil)
      normalize_branches!(branches, discriminator_column: discriminator_column, connection: connection).map do |branch|
        {
          name: branch.fetch(:name),
          value: branch.fetch(:value),
          where_condition: branch.fetch(:where_condition)
        }
      end
    end

    def validate_column!(column)
      name = column.to_s
      return if COLUMN_PATTERN.match?(name)

      raise ArgumentError, "predicate column must be a simple identifier, got #{name.inspect}"
    end

    def validate_operator!(operator)
      return if OPERATORS.include?(operator)

      raise ArgumentError, "unsupported predicate operator: #{operator.inspect} (allowed: #{OPERATORS.join(", ")})"
    end

    private :validate_column!, :validate_operator!
  end
end

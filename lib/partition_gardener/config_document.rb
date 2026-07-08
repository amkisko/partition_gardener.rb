module PartitionGardener
  module ConfigDocument
    SCHEMA_PATH = File.expand_path("../../docs/schemas/partition_garden.schema.json", __dir__)
    PLAN_SCHEMA_PATH = File.expand_path("../../docs/schemas/plan_report.schema.json", __dir__)

    PORTABLE_KEYS = %i[
      table_name
      layout
      bucket
      partition_key_column
      conflict_key
      active_months
      active_days
      active_weeks
      active_quarters
      active_years
      premake_months
      split_row_threshold
      move_batch_size
      statement_timeout
      retention_months
      retention_apply
      retention_keep_table
      retention_detach_concurrently
      hash_modulus
      maintenance_backend
      incremental_rebalance
      run_record_enabled
      analyze_after_rebalance
    ].freeze

    IMPORTABLE_LAYOUTS = %w[
      sliding_window
      rolling_current
      calendar_year
      premake_monthly
      integer_window
      hash_branches
    ].freeze

    ALLOWED_REGISTRY_KEYS = (
      %w[table_name layout partition_key_column conflict_key bucket] +
      PORTABLE_KEYS.map(&:to_s)
    ).uniq.freeze

    module_function

    def export(config)
      PORTABLE_KEYS.each_with_object({}) do |key, document|
        next unless config.key?(key)

        document[key] = config[key]
      end
    end

    def export_all(configs)
      configs.map { |config| export(config) }
    end

    def from_hash(document)
      layout = document.fetch("layout").to_sym
      table_name = document.fetch("table_name")
      partition_key_column = document.fetch("partition_key_column")
      conflict_key = document.fetch("conflict_key")
      options = document.except("table_name", "layout", "partition_key_column", "conflict_key").transform_keys(&:to_sym)

      case layout
      when :sliding_window
        import_sliding_window(
          table_name: table_name,
          partition_key_column: partition_key_column,
          conflict_key: conflict_key,
          **options
        )
      when :rolling_current
        Templates.rolling_current_monthly(
          table_name: table_name,
          partition_key_column: partition_key_column,
          conflict_key: conflict_key,
          **options
        )
      when :premake_monthly
        Templates.premake_monthly(
          table_name: table_name,
          partition_key_column: partition_key_column,
          conflict_key: conflict_key,
          **options
        )
      when :calendar_year
        Templates.calendar_year(
          table_name: table_name,
          partition_key_column: partition_key_column,
          conflict_key: conflict_key,
          **options
        )
      when :integer_window
        Templates.integer_window(
          table_name: table_name,
          partition_key_column: partition_key_column,
          conflict_key: conflict_key,
          **options
        )
      when :hash_branches
        Templates.hash_branches(
          table_name: table_name,
          partition_key_column: partition_key_column,
          conflict_key: conflict_key,
          **options
        )
      else
        raise ArgumentError, "layout #{layout} is not supported in JSON config import"
      end
    end

    def import_sliding_window(table_name:, partition_key_column:, conflict_key:, bucket: :month, **options)
      case bucket.to_sym
      when :day
        Templates.sliding_window_daily(
          table_name: table_name,
          partition_key_column: partition_key_column,
          conflict_key: conflict_key,
          **options
        )
      when :week
        Templates.sliding_window_weekly(
          table_name: table_name,
          partition_key_column: partition_key_column,
          conflict_key: conflict_key,
          **options
        )
      when :quarter
        Templates.sliding_window_quarterly(
          table_name: table_name,
          partition_key_column: partition_key_column,
          conflict_key: conflict_key,
          **options
        )
      else
        Templates.sliding_window_monthly(
          table_name: table_name,
          partition_key_column: partition_key_column,
          conflict_key: conflict_key,
          **options
        )
      end
    end

    def load_registry_file!(path)
      Registry.reset!
      payload = JSON.parse(File.read(path))

      case payload
      when Array
        payload.each { |document| register_validated_document!(document) }
      when Hash
        if payload["tables"].is_a?(Array)
          payload["tables"].each { |document| register_validated_document!(document) }
        else
          register_validated_document!(payload)
        end
      else
        raise ArgumentError, "registry file must be a JSON object or array"
      end
    end

    def validate_registry_document!(document)
      raise ArgumentError, "registry entry must be a JSON object" unless document.is_a?(Hash)

      validate_registry_required_keys!(document)
      validate_registry_unknown_keys!(document)
      validate_registry_layout!(document)
      validate_registry_core_strings!(document)
      validate_registry_conflict_key!(document)
      validate_registry_optional_bucket!(document)
      validate_registry_optional_maintenance_backend!(document)
      document
    end

    def validate_registry_required_keys!(document)
      missing_keys = %w[table_name layout partition_key_column conflict_key] - document.keys
      return if missing_keys.empty?

      raise ArgumentError, "registry entry missing required keys: #{missing_keys.join(", ")}"
    end

    def validate_registry_unknown_keys!(document)
      unknown_keys = document.keys - ALLOWED_REGISTRY_KEYS
      return if unknown_keys.empty?

      raise ArgumentError, "registry entry has unsupported keys: #{unknown_keys.join(", ")}"
    end

    def validate_registry_layout!(document)
      layout = document.fetch("layout")
      return if layout.is_a?(String) && IMPORTABLE_LAYOUTS.include?(layout)

      supported = IMPORTABLE_LAYOUTS.join(", ")
      raise ArgumentError, "layout #{layout.inspect} is not supported in JSON import (supported: #{supported}; composite and list_split require Ruby registration)"
    end

    def validate_registry_core_strings!(document)
      unless document.fetch("table_name").is_a?(String) && !document.fetch("table_name").empty?
        raise ArgumentError, "table_name must be a non-empty string"
      end

      unless document.fetch("partition_key_column").is_a?(String) && !document.fetch("partition_key_column").empty?
        raise ArgumentError, "partition_key_column must be a non-empty string"
      end
    end

    def validate_registry_conflict_key!(document)
      conflict_key = document.fetch("conflict_key")
      return if conflict_key.is_a?(Array) && conflict_key.any? && conflict_key.all? { |column| column.is_a?(String) && !column.empty? }

      raise ArgumentError, "conflict_key must be a non-empty array of strings"
    end

    def validate_registry_optional_bucket!(document)
      return unless document.key?("bucket")

      bucket = document.fetch("bucket")
      return if bucket.is_a?(String) && %w[day week month quarter year].include?(bucket)

      raise ArgumentError, "bucket must be one of: day, week, month, quarter, year"
    end

    def validate_registry_optional_maintenance_backend!(document)
      return unless document.key?("maintenance_backend")

      backend = document.fetch("maintenance_backend")
      return if backend.is_a?(String) && %w[gardener pg_partman hybrid_layout_only].include?(backend)

      raise ArgumentError, "maintenance_backend must be gardener, pg_partman, or hybrid_layout_only"
    end

    def register_validated_document!(document)
      Registry.register(from_hash(validate_registry_document!(document)))
    end
  end
end

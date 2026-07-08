module PartitionGardener
  module MaintenanceBackend
    GARDENER = :gardener
    PG_PARTMAN = :pg_partman
    HYBRID_LAYOUT_ONLY = :hybrid_layout_only

    class ValidationError < ArgumentError; end

    module_function

    def normalize(backend)
      backend&.to_sym || GARDENER
    end

    def gardener_owned?(config)
      normalize(config[:maintenance_backend]) != PG_PARTMAN
    end

    def skipped?(config)
      normalize(config[:maintenance_backend]) == PG_PARTMAN
    end

    def hybrid?(config)
      normalize(config[:maintenance_backend]) == HYBRID_LAYOUT_ONLY
    end

    def partman_parent_configured?(table_name)
      Connection.partman_parent_configured?(table_name)
    rescue
      false
    end

    def validate!(config)
      violations = validation_messages(config)
      return if violations.empty?

      violations.each do |message|
        if PartitionGardener.configuration.strict_maintenance_backend_validation
          raise ValidationError, message
        end

        PartitionGardener.configuration.notify(
          "[PartitionGardener] #{message}",
          context: {
            table_name: config[:table_name],
            maintenance_backend: normalize(config[:maintenance_backend])
          }
        )
      end
    end

    def validation_messages(config)
      backend = normalize(config[:maintenance_backend])
      table_name = config[:table_name]
      partman_row = partman_parent_configured?(table_name)
      messages = []

      if backend == PG_PARTMAN && !partman_row
        messages << "#{table_name} maintenance_backend is pg_partman but partman.part_config has no row"
      end

      if backend == GARDENER && partman_row
        messages << "#{table_name} is registered for gardener but partman.part_config also lists this parent; pick one maintainer"
      end

      if hybrid?(config) && !partman_row
        messages << "#{table_name} hybrid_layout_only expects partman premake on the same parent"
      end

      messages
    end
  end
end

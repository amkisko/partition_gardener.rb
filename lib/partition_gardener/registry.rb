module PartitionGardener
  module Registry
    class << self
      def register(config)
        normalized = Templates.normalize(config)
        normalized[:maintenance_backend] = MaintenanceBackend.normalize(normalized[:maintenance_backend])
        tables.delete_if { |entry| entry[:table_name] == normalized[:table_name] }
        tables << normalized
        MaintenanceBackend.validate!(normalized)
        normalized
      end

      def register_template(template_name, **options)
        builder = Templates.public_method(template_name)
        register(builder.call(**options))
      rescue NameError
        raise ArgumentError, "unknown template: #{template_name.inspect}"
      end

      def register_all(configs)
        configs.map { |config| register(config) }
      end

      def each_table_config(&block)
        expanded_table_configs.each(&block)
      end

      def expanded_table_configs
        expanded_tables
      end

      def configs_for_table(table_name)
        name = table_name.to_s
        registered = tables.find { |config| config[:table_name].to_s == name }
        return Templates.expand(registered) if registered&.fetch(:layout, nil) == :composite

        expanded_table_configs.select do |config|
          config[:table_name].to_s == name || config[:parent_table_name].to_s == name
        end
      end

      def find_by_table_name(table_name)
        expanded_tables.find { |config| config[:table_name].to_s == table_name.to_s }
      end

      def hot_switch_partition_config(table_name)
        config = find_by_table_name(table_name)
        return nil unless config

        {
          table_name: config[:table_name],
          partition_name_format: config[:partition_name_format],
          partition_definition: config[:partition_definition],
          partitions_to_create: lambda { |today|
            [DateCalendar.beginning_of_month(today), DateCalendar.beginning_of_month(DateCalendar.next_month(today))]
          }
        }
      end

      def tables
        @tables ||= []
      end

      def map(&block)
        each_table_config.map(&block)
      end

      # Prefer `.tables`. Kept for callers that used the old constant name.
      def self.TABLES
        tables
      end

      def reset!
        @tables = []
      end

      private

      def expanded_tables
        tables.flat_map { |config| Templates.expand(config) }
      end
    end
  end
end

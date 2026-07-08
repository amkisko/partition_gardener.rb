module PartitionGardener
  class MissingDefaultPartition < StandardError; end

  class DefaultPartition
    include Naming

    def self.ensure!(config, executor: nil)
      new(config, executor: executor).ensure!
    end

    def initialize(config, executor: nil)
      @config = config
      @executor = executor || Executor.for_config(config)
    end

    def ensure!
      table_name = @config[:table_name]
      return unless Connection.table_is_partitioned?(table_name)
      return unless Strategy.for(@config).default_partition_required?

      default_name = default_partition_name(table_name)

      if Connection.partition_exists?(default_name)
        attach_existing_default!(table_name, default_name)
      else
        create_default!(table_name, default_name)
      end

      return if Connection.partition_attached?(table_name, default_name)

      raise MissingDefaultPartition,
        "Default partition #{default_name} is required for #{table_name} but is not attached"
    end

    private

    def connection
      Connection.connection
    end

    def attach_existing_default!(table_name, default_name)
      return if Connection.partition_attached?(table_name, default_name)

      @executor.attach_default_partition(table_name, default_name)
    end

    def create_default!(table_name, default_name)
      sql = <<~SQL
        CREATE TABLE IF NOT EXISTS #{Connection.quoted_table(default_name)} PARTITION OF #{Connection.quoted_table(table_name)} DEFAULT
      SQL
      connection.execute(sql)
    end
  end
end

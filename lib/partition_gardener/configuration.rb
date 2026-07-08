module PartitionGardener
  class Configuration
    attr_accessor :notifier,
      :connection_resolver,
      :statement_timeout_wrapper,
      :today_resolver,
      :schema_name,
      :continue_on_error,
      :advisory_lock_mode,
      :analyze_after_rebalance,
      :incremental_rebalance,
      :run_record_enabled,
      :retention_detach_concurrently,
      :strict_maintenance_backend_validation,
      :current_run_metrics

    attr_writer :run_record_store

    def initialize
      @notifier = ->(_message_or_error, context: {}) {}
      @connection_resolver = method(:default_connection_resolver)
      @statement_timeout_wrapper = ->(_timeout, &block) { block.call }
      @today_resolver = -> { Date.today }
      @schema_name = "public"
      @continue_on_error = true
      @advisory_lock_mode = :transaction
      @analyze_after_rebalance = false
      @incremental_rebalance = true
      @run_record_enabled = true
      @run_record_store = nil
      @retention_detach_concurrently = false
      @strict_maintenance_backend_validation = false
      @current_run_metrics = nil
    end

    def run_record_store
      @run_record_store ||= default_run_record_store
    end

    def connection
      resolved = @connection_resolver.call
      raise ArgumentError, "PartitionGardener connection is not configured" unless resolved

      resolved
    end

    def notify(message_or_error, context: {})
      @notifier.call(message_or_error, context: context)
    end

    def with_statement_timeout(timeout, &block)
      @statement_timeout_wrapper.call(timeout, &block)
    end

    def today
      @today_resolver.call
    end

    private

    def default_run_record_store
      return MemoryRunRecordStore.new unless sql_run_record_store_available?

      SqlRunRecordStore.new
    rescue
      MemoryRunRecordStore.new
    end

    def default_connection_resolver
      return ActiveRecord::Base.connection if defined?(ActiveRecord::Base)

      database_url = ENV["DATABASE_URL"]
      return nil if database_url.nil? || database_url.empty?

      @pg_connection ||= PgConnection.connect(database_url).tap do
        # Standalone maintenance runs many statements; session locks avoid one long transaction.
        @advisory_lock_mode = :session if @advisory_lock_mode == :transaction
      end
    end

    def sql_run_record_store_available?
      return true if defined?(ActiveRecord::Base)

      database_url = ENV["DATABASE_URL"]
      !database_url.nil? && !database_url.empty?
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
      configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end

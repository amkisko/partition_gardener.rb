module PartitionGardener
  module AdvisoryLock
    LOCK_NAMESPACE = "partition_gardener"

    module_function

    def with_table_lock(table_name, &block)
      case PartitionGardener.configuration.advisory_lock_mode
      when :transaction
        with_transaction_lock(table_name, &block)
      else
        with_session_lock(table_name, &block)
      end
    end

    def with_session_lock(table_name)
      connection = Connection.connection
      lock_sql = lock_expression(connection, table_name)
      acquired = false
      acquired = connection.execute("SELECT pg_try_advisory_lock(#{lock_sql})").first.values.first
      acquired = acquired == true || acquired == "t"
      raise LockNotAcquired, "session advisory lock not acquired for #{table_name}" unless acquired

      yield
    ensure
      connection.execute("SELECT pg_advisory_unlock(#{lock_sql})") if connection && lock_sql && acquired
    end

    def with_transaction_lock(table_name)
      connection = Connection.connection
      lock_sql = lock_expression(connection, table_name)

      connection.transaction do
        acquired = connection.execute("SELECT pg_try_advisory_xact_lock(#{lock_sql})").first.values.first
        acquired = acquired == true || acquired == "t"
        raise LockNotAcquired, "transaction advisory lock not acquired for #{table_name}" unless acquired

        yield
      end
    end

    def lock_expression(connection, table_name)
      namespace = connection.quote(LOCK_NAMESPACE)
      table = connection.quote(table_name)
      "hashtext(#{namespace}), hashtext(#{table})"
    end
  end
end

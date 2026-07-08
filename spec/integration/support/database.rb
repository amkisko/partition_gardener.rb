require "securerandom"
require "uri"
require "active_record"

module PartitionGardener
  module Integration
    module Database
      DEFAULT_URL = "postgres://postgres:postgres@127.0.0.1:5432/partition_gardener_test"

      module_function

      def enabled?
        ENV["INTEGRATION"] == "1"
      end

      def connect!
        ensure_database!
        ActiveRecord::Base.establish_connection(connection_options)
        connection.execute("SELECT 1")
      end

      def ensure_database!
        url = resolved_database_url
        uri = URI.parse(url)
        database_name = uri.path.delete_prefix("/")
        return if database_name.empty?

        admin_uri = uri.dup
        admin_uri.path = "/postgres"

        PG.connect(admin_uri.to_s) do |admin_connection|
          exists = admin_connection.exec_params(
            "SELECT 1 FROM pg_database WHERE datname = $1",
            [database_name]
          ).any?

          next if exists

          admin_connection.exec("CREATE DATABASE #{quote_identifier(database_name)}")
        end
      end

      def quote_identifier(name)
        %("#{name.gsub('"', '""')}")
      end

      def connection
        ActiveRecord::Base.connection
      end

      def resolved_database_url
        database_url = ENV.fetch("DATABASE_URL", DEFAULT_URL)
        # polyrun run-shards may set DATABASE_URL to the shard DB; polyrun env (CI) does not —
        # only add _{idx} when missing, so we never double-suffix (e.g. _0_0).
        if database_url.match?(/\Apostgres(?:ql)?:\/\//) && ENV["POLYRUN_SHARD_TOTAL"].to_i > 1
          idx = Integer(ENV.fetch("POLYRUN_SHARD_INDEX", "0"), exception: false)
          idx = 0 if idx.nil?
          if (match = database_url.match(%r{/([^/?]+)(\?|$)})) && !match[1].end_with?("_#{idx}")
            begin
              require "polyrun"
              database_url = Polyrun::Database::Shard.database_url_with_shard(database_url, idx)
            rescue LoadError
              # polyrun optional for contributors without the gem
            end
          end
        end
        database_url
      end

      def connection_options
        {url: resolved_database_url}
      end

      def configure_pg_connection!(today: Date.new(2026, 7, 5))
        database_url = resolved_database_url
        pg_connection = PartitionGardener::PgConnection.connect(database_url)

        PartitionGardener.configure do |configuration|
          configuration.connection_resolver = -> { pg_connection }
          configuration.advisory_lock_mode = :session
          configuration.today_resolver = -> { today }
          configuration.notifier = ->(_message, context: {}) {}
          configuration.run_record_store = MemoryRunRecordStore.new
          configuration.incremental_rebalance = true
          configuration.run_record_enabled = true
        end

        pg_connection
      end

      def configure_gardener!(today: Date.new(2026, 7, 5))
        PartitionGardener.configure do |configuration|
          configuration.connection_resolver = -> { connection }
          configuration.today_resolver = -> { today }
          configuration.notifier = ->(_message, context: {}) {}
          configuration.run_record_store = MemoryRunRecordStore.new
          configuration.incremental_rebalance = true
          configuration.run_record_enabled = true
        end
      end
    end
  end
end

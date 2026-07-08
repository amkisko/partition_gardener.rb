require "date"

require_relative "partition_gardener/version"
require_relative "partition_gardener/date_calendar"
require_relative "partition_gardener/date_bucket"
require_relative "partition_gardener/stdlib_extensions"
require "pg"
require_relative "partition_gardener/pg_connection"
require_relative "partition_gardener/blank"
require_relative "partition_gardener/predicate"
require_relative "partition_gardener/memory_run_record_store"
require_relative "partition_gardener/sql_run_record_store"
require_relative "partition_gardener/configuration"
require_relative "partition_gardener/naming"
require_relative "partition_gardener/plan"
require_relative "partition_gardener/connection"
require_relative "partition_gardener/executor"
require_relative "partition_gardener/default_partition"
require_relative "partition_gardener/strategy/requires_default_partition"
require_relative "partition_gardener/strategy/cursor_columns"
require_relative "partition_gardener/strategy/date_range"
require_relative "partition_gardener/strategy/integer_range"
require_relative "partition_gardener/strategy/hash_branches"
require_relative "partition_gardener/strategy/list_split"
require_relative "partition_gardener/strategy/composite"
require_relative "partition_gardener/strategy"
require_relative "partition_gardener/layout/three_area"
require_relative "partition_gardener/layout/zone_segments"
require_relative "partition_gardener/layout/sliding_window"
require_relative "partition_gardener/layout/calendar_year"
require_relative "partition_gardener/layout/integer_window"
require_relative "partition_gardener/planner"
require_relative "partition_gardener/plan_diff"
require_relative "partition_gardener/gap_detection"
require_relative "partition_gardener/plan_report"
require_relative "partition_gardener/run_record"
require_relative "partition_gardener/plan_applier"
require_relative "partition_gardener/hash_routing"
require_relative "partition_gardener/maintenance_backend"
require_relative "partition_gardener/run_metrics"
require_relative "partition_gardener/date_range_maintenance"
require_relative "partition_gardener/premake_monthly_maintenance"
require_relative "partition_gardener/templates"
require_relative "partition_gardener/advisory_lock"
require_relative "partition_gardener/lock_not_acquired"
require_relative "partition_gardener/missing_conflict_index"
require_relative "partition_gardener/orphaned_rebalance_staging"
require_relative "partition_gardener/unmoved_rows_remaining"
require_relative "partition_gardener/run_failed"
require_relative "partition_gardener/audit"
require_relative "partition_gardener/archive_retention"
require_relative "partition_gardener/registry"
require_relative "partition_gardener/config_document"
require_relative "partition_gardener/cli"
require_relative "partition_gardener/migration/hot_switch_concern"

module PartitionGardener
  MOVE_BATCH_SIZE = 10_000
  FUTURE_MONTH_PARTITION_ROW_THRESHOLD = 100_000
  DEFAULT_STATEMENT_TIMEOUT = 300

  class << self
    def run!(statement_timeout: DEFAULT_STATEMENT_TIMEOUT, job_class_name: "PartitionGardener", continue_on_error: configuration.continue_on_error, dry_run: false, table_name: nil)
      return plan_all if dry_run

      errors = []
      table_results = []
      filter_table = table_name
      configs = filter_table ? Registry.configs_for_table(filter_table) : Registry.expanded_table_configs

      configs.each do |config|
        table_name = config[:table_name]
        table_timeout = config.fetch(:statement_timeout, statement_timeout)
        metrics = RunMetrics.new(table_name)

        configuration.with_statement_timeout(table_timeout) do
          Connection.clear_attached_partitions_cache!

          unless Connection.table_is_partitioned?(table_name)
            metrics.mark_skipped!("not_partitioned")
            table_results << metrics
            next
          end

          if MaintenanceBackend.skipped?(config)
            metrics.mark_skipped!("maintenance_backend_pg_partman")
            table_results << metrics
            next
          end

          configuration.current_run_metrics = metrics

          AdvisoryLock.with_table_lock(table_name) do
            DefaultPartition.ensure!(config)
            maintenance_for(config, job_class_name: job_class_name).run!
          end

          metrics.finish!
          emit_run_metadata(metrics, job_class_name: job_class_name)
          table_results << metrics
        rescue LockNotAcquired => error
          metrics.mark_skipped!("lock_not_acquired")
          configuration.notify(
            "[PartitionGardener] skipped #{table_name}: #{error.message}",
            context: {
              table_name: table_name,
              job: job_class_name,
              action: "lock"
            }
          )
          table_results << metrics
        rescue => error
          metrics.finish!
          configuration.notify(
            error,
            context: {
              table_name: table_name,
              job: job_class_name,
              action: "run",
              run_metadata: metrics.to_h
            }
          )
          errors << error
          table_results << metrics
          raise unless continue_on_error
        ensure
          configuration.current_run_metrics = nil
        end
      end

      summary = RunSummary.new(tables: table_results, errors: errors)
      raise RunFailed, errors if errors.any?

      summary
    end

    def audit(table_name)
      configs = Registry.configs_for_table(table_name)
      raise ArgumentError, "no config for #{table_name}" if configs.empty?

      if configs.one?
        Audit.call(table_name, config: configs.first)
      else
        configs.map { |config| Audit.call(config[:table_name], config: config) }
      end
    end

    def plan(table_name: nil, config: nil)
      if config
        return PlanReport.build(config)
      end

      raise ArgumentError, "table_name or config is required" unless table_name

      configs = Registry.configs_for_table(table_name)
      raise ArgumentError, "no config for #{table_name}" if configs.empty?

      if configs.one?
        PlanReport.build(configs.first)
      else
        configs.map { |entry| PlanReport.build(entry) }
      end
    end

    def maintenance_for(config, job_class_name: "PartitionGardener")
      case config.fetch(:layout)
      when :composite
        CompositeMaintenance.new(config, job_class_name: job_class_name)
      when :premake_monthly
        PremakeMonthlyMaintenance.new(config, job_class_name: job_class_name)
      else
        ThreeAreaMaintenance.new(config, job_class_name: job_class_name)
      end
    end

    def emit_run_metadata(metrics, job_class_name:)
      configuration.notify(
        "[PartitionGardener] Finished #{metrics.table_name}",
        context: {
          table_name: metrics.table_name,
          job: job_class_name,
          action: "run_metadata",
          run_metadata: metrics.to_h
        }
      )
    end

    def plan_all
      reports = []
      Registry.each_table_config do |config|
        next unless Connection.table_is_partitioned?(config[:table_name])

        reports << PlanReport.build(config).to_h
      end
      reports
    end

    def plan_all_tables
      Registry.each_table_config.map { |config| PlanReport.build(config) }
    end

    private :plan_all, :emit_run_metadata
  end
end

require_relative "partition_gardener/rails" if defined?(Rails::Railtie)

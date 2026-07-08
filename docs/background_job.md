# Background job integration

Partition Gardener does not ship an Active Job class, queue adapter, or cron schedule. The gem exposes `PartitionGardener.run!`; the host application owns scheduling, queue choice, and concurrency policy.

## Minimal job

```ruby
class PartitionMaintenanceJob < ApplicationJob
  queue_as :cleaners

  def perform
    PartitionGardener.run!(job_class_name: self.class.name)
  end
end
```

Pass `job_class_name:` so notifier context and run metadata identify the host job (for example in Sentry or structured logs).

## Recommended host-app practices

### One maintainer at a time per table

Gardener acquires a per-table PostgreSQL advisory lock during `run!`. A second worker skips that table with `lock_not_acquired` rather than blocking forever.

Still limit full maintenance runs to one concurrent job for the whole registry when possible. Two jobs iterating all tables waste work and inflate log noise even when locks serialize per table.

Example with Good Job:

```ruby
class PartitionMaintenanceJob < ApplicationJob
  queue_as :cleaners

  include GoodJob::ActiveJobExtensions::Concurrency

  good_job_control_concurrency_with(
    key: -> { self.class.name },
    total_limit: 1
  )

  def perform
    PartitionGardener.run!(job_class_name: self.class.name)
  end
end
```

Sidekiq, Solid Queue, and other adapters have similar uniqueness or concurrency controls — use whatever matches the host app.

### Schedule

Sliding-window maintenance is designed for periodic runs, not per-insert work. How often to call `run!` depends on service load and move tolerance.

#### Scheduled maintenance (default)

Run nightly or off-peak when row moves on a fixed cadence are acceptable and audit usually stays clean between runs.

Typical cadence:

- Production: once per day after the business-date rollover the app uses (`today_resolver`)
- Staging: same schedule to catch config drift before production
- After cutover: run manually or on the next schedule slot; verify default partition row count reaches zero

#### Indicator-driven maintenance

Some services should not run maintenance nightly. Defer `run!` until audit indicators clearly show need: non-zero default, horizon below threshold, heat split warranted, or gap warnings. Schedule read-only `audit` on a fixed cadence; enqueue `apply` / `run!` only when warnings persist or breach operator thresholds ([monitoring.md](monitoring.md), [decision_flow.md](decision_flow.md#maintenance-cadence)).

Services on this cadence should serve hot-path totals and rollups from bucket-keyed snapshot tables, not live aggregates across all partitions ([partition_landscape.md](partition_landscape.md#aggregates-totals-and-snapshots)). Snapshot freshness and drift checks become part of the maintenance story alongside layout audit.

Example gate job:

```ruby
class PartitionAuditJob < ApplicationJob
  queue_as :cleaners

  def perform
    PartitionGardener::Registry.each do |config|
      result = PartitionGardener.audit(config[:table_name])
      next unless needs_maintenance?(result)

      PartitionMaintenanceJob.perform_later(table_name: config[:table_name])
    end
  end

  private

  def needs_maintenance?(audit_result)
    audit_result.warnings.any? { |warning| threshold_breached?(warning) }
  end
end
```

Tune `needs_maintenance?` to your SLOs; do not run `apply` on a single transient spike without a second audit or sustained breach.

Cron, Good Job cron, or an external scheduler (Kubernetes CronJob, systemd timer) are all valid. The gem does not prescribe one.

### Statement timeouts

Wrap maintenance in the host database timeout helper via global config:

```ruby
PartitionGardener.configure do |config|
  config.statement_timeout_wrapper = ->(timeout, &block) {
    DatabaseTimeout.statement_timeout(timeout, &block)
  }
end
```

Per-table overrides: `statement_timeout: 10.minutes` on the registry entry.

### Error handling

Default `continue_on_error: true` finishes other tables when one fails, then raises `PartitionGardener::RunFailed` with all errors. The job should retry or alert on `RunFailed`.

To fail fast on the first table error:

```ruby
PartitionGardener.run!(continue_on_error: false, job_class_name: self.class.name)
```

Notifier hook — wire to your reporting pipeline:

```ruby
PartitionGardener.configure do |config|
  config.notifier = ->(message_or_error, context: {}) {
    ActionReporter.notify(message_or_error, context: context)
  }
end
```

### Single-table runs

For targeted recovery after an incident:

```ruby
PartitionGardener.run!(table_name: "audits", job_class_name: self.class.name)
```

The CLI `apply` command accepts one table by default; pass `--all` for the full registry ([cli.md](cli.md)).

## What the job should not do

- Do not reimplement premake, default drain, or tail rebalance in the job — call `run!` only.
- Do not register the same parent with both partman and gardener unless using `hybrid_layout_only` intentionally ([tooling_split.md](tooling_split.md)).
- Do not run maintenance inside request cycles.

## Alternatives to a job

`bundle exec partition_gardener --rails apply TABLE` — manual ops, CI smoke, one-off recovery.

`PartitionGardener.run!(dry_run: true)` — pre-deploy plan review.

`PartitionGardener.audit("audits")` — read-only layout audit without writes ([audit_reference.md](audit_reference.md)).

## Rollup and snapshot jobs

Dashboard totals and cross-period aggregates should refresh in separate background jobs, bucketed like partitions ([partition_landscape.md](partition_landscape.md#aggregates-totals-and-snapshots)). Materialized views are not a substitute for bucket-keyed snapshot tables on hot paths ([materialized views](partition_landscape.md#materialized-views)). Schedule rollup recompute after maintenance when `rows_moved` is high, or on a fixed cadence with drift checks ([monitoring.md](monitoring.md)).

## Related

- [configuration.md](configuration.md) — global and per-table options
- [cli.md](cli.md) — plan, audit, apply without enqueueing a job
- [operations.md](operations.md) — incident runbook

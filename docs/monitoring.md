# Monitoring and SLOs

What to measure and alert on for partitioned tables maintained by Partition Gardener. Pair with [operations.md](operations.md) for remediation steps.

## Suggested metrics

Emit from maintenance or audit jobs, CLI audit cron, or a thin wrapper around `PartitionGardener.audit`. Indicator-driven services audit on a schedule and call `run!` only when metrics breach thresholds ([decision_flow.md](decision_flow.md#maintenance-cadence)).

`partition_gardener.default_row_count` — from `audit` per table. Gauge; label `table_name`.

`partition_gardener.horizon_days` — from `audit` per table. Gauge; null if not computable.

`partition_gardener.attached_child_count` — from `audit` per table. Gauge.

`partition_gardener.audit_warning_count` — from `audit` per table. Gauge.

`partition_gardener.run.duration_ms` — from `RunSummary.tables[]`. Histogram per table.

`partition_gardener.run.rows_moved` — from `RunSummary.tables[]`. Counter or gauge per run.

`partition_gardener.run.skipped` — from `RunSummary`. Counter by `skip_reason`.

`partition_gardener.run.failed` — job rescue on `RunFailed`. Counter.

`partition_gardener.snapshot.drift` — application rollup reconcile. Gauge per bucket; see landscape doc.

`partition_gardener.snapshot.stale_seconds` — `now - computed_at` on snapshots. Gauge.

## Alert rules (starting points)

Tune thresholds per table size and bucket grain.

`default_row_count > 0` for 2+ consecutive audit days — warning. Layout or insert contract slipping.

`default_row_count` growing week over week — page. Active mis-routing.

`horizon_days < 30` (monthly buckets) — warning. Premake or rebalance behind.

`horizon_days < 7` — page. Imminent insert routing risk.

`RunFailed` on nightly job — page. At least one table did not complete.

`rows_moved` > baseline × 5 — warning. Large drain or first rebalance; watch I/O and replicas.

`skip_reason = lock_not_acquired` on every table — warning. Duplicate schedulers.

`attached_child_count > 200` — warning. Catalog pressure ([audit](audit_reference.md)).

`snapshot.drift` above threshold — warning. Rollup pipeline bug or move window not reconciled.

`snapshot.stale_seconds` > SLA for closed periods — warning. Background recompute stuck.

## SLO sketches

Document per product; examples:

Default empty: 95% of audit days show `default_row_count = 0` within 24h of any spike.

Horizon: `horizon_days >= 30` for all monthly tables 99% of audit days.

Job success (scheduled maintenance): nightly `run!` completes without `RunFailed` 99.5% of nights.

Layout invariants (indicator-driven maintenance): audit clears breach thresholds within SLA after a triggered `apply`; zero sustained default growth between applies.

Snapshot freshness: closed-month totals `computed_at` within 6h of period close.

## Dashboards

Minimum panels per production partitioned table:

1. Default row count (time series)
2. Horizon days
3. Last run `rows_moved` and duration
4. Audit warning list (table)
5. Snapshot drift and staleness (application metrics)

## Notifier hook

Wire global `notifier` to your pipeline ([configuration.md](configuration.md)):

```ruby
PartitionGardener.configure do |config|
  config.notifier = ->(message_or_error, context: {}) {
    Metrics.increment("partition_gardener.notify", tags: context)
    ErrorTracker.notify(message_or_error, extra: context)
  }
end
```

Retention drops and dry-run retention logs also use `notifier`.

## Synthetic checks

Optional daily job (read-only):

```ruby
PartitionGardener::Registry.each do |config|
  result = PartitionGardener.audit(config[:table_name])
  report_to_metrics(result)
end
```

Cheaper than full `apply`; catches drift between maintenance runs.

## Related

- [audit_reference.md](audit_reference.md) — field meanings
- [operations.md](operations.md) — incident response
- [retention.md](retention.md) — alerts before drop
- [background_job.md](background_job.md) — job concurrency

# Operations runbook

Day-to-day maintenance for partitioned tables registered with Partition Gardener. Use this page when audit warnings fire, a nightly job fails, or you need to recover a single table without rereading the whole configuration reference.

## Daily rhythm

Two maintenance postures are common. Pick one per service; do not assume every registered table needs the same cadence ([decision_flow.md](decision_flow.md#maintenance-cadence)).

### Scheduled maintenance

1. Nightly `PartitionGardener.run!` (or CLI `apply` in non-Rails environments) after business-date rollover (`today_resolver`).
2. Morning check: audit JSON for default rows, horizon, and gaps ([audit_reference.md](audit_reference.md)).
3. Alert on `RunFailed`, sustained default growth, or horizon below threshold ([monitoring.md](monitoring.md)).

### Indicator-driven maintenance

1. Scheduled read-only `audit` (hourly or daily); no `apply` on a fixed calendar unless indicators demand it.
2. Enqueue `run!` for a table when audit warnings persist: default rows, horizon below threshold, heat above split threshold, or layout gaps.
3. Same alerts as scheduled maintenance; add snapshot drift and staleness when hot paths read rollups ([partition_landscape.md](partition_landscape.md#aggregates-totals-and-snapshots)).
4. After `apply`, recompute snapshot buckets affected by high `rows_moved` before treating the incident closed.

Indicator-driven services depend on efficient bucket-keyed snapshots on hot paths so deferred maintenance does not push reporting onto full partition scans.

See [background_job.md](background_job.md) for job concurrency and [retention.md](retention.md) for archive detach and drop policy.

## Commands by situation

Read-only audit: `bundle exec partition_gardener --rails audit TABLE --pretty`

Read-only layout diff: `bundle exec partition_gardener --rails plan TABLE --pretty`

Apply one table: `bundle exec partition_gardener --rails apply --confirm TABLE`

Apply full registry: `bundle exec partition_gardener --rails apply --all`

Ruby dry-run: `PartitionGardener.run!(dry_run: true, table_name: "events")`

Ruby single table: `PartitionGardener.run!(table_name: "events", job_class_name: "Ops")`

Always `plan` before the first `apply` after a registry or template change. In production, prefer the scheduled job; use CLI `apply` for targeted recovery.

## RunSummary fields

`run!` and CLI `apply` return `RunSummary` JSON (`schema_version` 1.0):

`tables[].table_name` — parent table processed.

`tables[].duration_ms` — wall time for that table.

`tables[].plan_signature` — hash of target segments; changes when layout plan changes.

`tables[].rows_moved` — rows moved during default drain and tail rebalance.

`tables[].skipped` — true when the table was not maintained.

`tables[].skip_reason` — e.g. `lock_not_acquired`, `not_partitioned`, `pg_partman`.

`errors` — messages collected when `continue_on_error` is true; run still raises `RunFailed` at end if non-empty.

Interpretation:

- `lock_not_acquired` — another worker holds the advisory lock; usually harmless if one job owns maintenance. Investigate duplicate cron or overlapping deploy hooks.
- High `rows_moved` after a quiet period — default drain catching up, or first run after cutover. Expect elevated I/O; watch replica lag ([application_contract.md](application_contract.md)).
- `errors` non-empty — at least one table failed; other tables may have completed. Fix the failing table, then rerun that table only.

## Audit warnings to actions

Full catalog: [audit_reference.md](audit_reference.md). Quick map:

default partition has N rows (N > 0) — likely inserts outside bounds, premake lag, or wrong partition key on writes. Action: `plan` then `apply`; fix application inserts; check horizon.

default partition is missing — incomplete creation migration. Action: create default child; never leave parent without default on RANGE layouts that require it.

partition horizon is X days ahead (below 30) — premake or sliding-window rebalance behind. Action: `apply`; verify `active_months` / premake settings.

partition gap: uncovered range between … — overlapping manual DDL or interrupted rebalance. Action: `plan` to see target; `apply`; avoid hand-attaching overlapping children.

no attached tail partition extends to MAXVALUE — missing `_future` or open tail. Action: `apply`; compare `attached_segments` vs `target_segments` in plan.

attached child count is N (high catalog pressure) — too many archive months attached or manual sprawl. Action: tighten `active_months`; enable `retention_months`; review [naming.md](naming.md) for orphan children.

table is not a partitioned table — registry typo or wrong connection. Action: fix registry; point `connection_resolver` at correct database.

## Failed or partial runs

Gardener persists checkpoints in `partition_gardener_run_records` when `run_record_enabled` is true (default).

1. Read `errors` and notifier context (`table_name`, `action`).
2. `audit TABLE` — confirm default count and gaps unchanged or worse.
3. `plan TABLE` — if `changed` is true, layout still needs work.
4. Retry `run!(table_name: TABLE)` — incremental rebalance resumes when `plan_signature` matches the stored record.
5. If a staging partition `TABLE_rebalance_staging` exists and blocks progress, inspect row count and consult gem issues; orphaned staging outside a matching `plan_signature` is cleared on the next full apply.

Set `continue_on_error: false` only when you want the job to stop on the first table failure.

## Retention during operations

When `retention_months` is set, gardener detaches (and optionally drops) archive children older than the cutoff after layout work. See [retention.md](retention.md) for legal hold, `retention_keep_table`, and backup checks before drop.

`retention_detach_concurrently: true` reduces lock duration on detach; requires PostgreSQL 14+ and no long transactions holding the partition.

## Index review after large layout changes

When `rows_moved` is high after rebalance, heat splits, or template upgrades, query plans may need new indexes on hot children. Review manually or run [Dexter](https://github.com/ankane/dexter) against recent workload ([related_postgres_tooling.md](related_postgres_tooling.md)). Gardener does not create indexes; `plan` / `apply` only change partition bounds and row placement.

## Sharded registries

Run maintenance per shard connection:

```ruby
ShardRecord.connected_to_all_shards do
  PartitionGardener.run!(job_class_name: self.class.name)
end
```

Or set `connection_resolver` on a shard-specific registry load. Audit and apply are per connection; there is no cross-shard summary in one CLI invocation.

## What not to do in incidents

- Do not hand-`DROP` archive children without retention policy and backup review.
- Do not attach overlapping RANGE children to fix gaps without reading `plan` output.
- Do not run two full `apply --all` jobs concurrently without concurrency limits.
- Do not disable default drain to “fix” slowness; fix bounds and inserts instead.

## Related

- [audit_reference.md](audit_reference.md) — warning and plan field reference
- [monitoring.md](monitoring.md) — metrics and alerts
- [cutover.md](cutover.md) — first-time migration and rollback
- [configuration.md](configuration.md) — registry options
- [cli.md](cli.md) — CLI flags

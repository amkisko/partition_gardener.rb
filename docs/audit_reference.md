# Audit and plan reference

Human-readable catalog for `PartitionGardener.audit`, `PartitionGardener.plan`, CLI `audit` / `plan`, and `RunSummary` output. JSON schemas: [plan_report.schema.json](schemas/plan_report.schema.json), [partition_garden.schema.json](schemas/partition_garden.schema.json).

## Audit result (`schema_version` 1.0)

`table_name` (string) — parent table.

`partitioned` (boolean) — declarative parent exists.

`default_row_count` (integer) — rows in `{table}_default`.

`attached_child_count` (integer) — attached children including default.

`horizon_days` (integer or null) — days from `today` to latest finite upper bound among children.

`gaps` (array) — structural range gaps in tail layout.

`warnings` (array of string) — human-readable issues.

Horizon warning threshold: 30 days (`Audit::HORIZON_WARNING_DAYS`). High child count warning: more than 200 attached children.

## Audit warning catalog

`{table} is not a partitioned table` — parent missing or not partitioned. Fix migration; check `connection_resolver`.

`default partition {name} has {n} rows` — rows routed to default. Fix inserts; run `apply` to drain.

`default partition {name} is missing` — no default child. Add default partition for layouts that require it.

`partition horizon is {d} days ahead (below 30)` — future bound too close. Run `apply`; check premake / `active_*`.

`attached child count is {n} (high catalog pressure)` — too many children. Retention; reduce `active_months`; remove orphans.

`partition gap: uncovered range between {a} and {b} ({from}..{to})` — hole between adjacent tail segments. `plan` then `apply`; remove overlapping manual DDL.

`partition gap: no attached tail partition extends to MAXVALUE` — missing future/open tail. `apply` to attach `_future`.

Gap objects include `range_start`, `range_end`, and `message`.

## Plan report

`schema_version` — `"1.0"`.

`table_name` — parent.

`layout` — registry layout symbol (e.g. `sliding_window`).

`changed` — `true` when operations would mutate catalog or move rows.

`plan_signature` — stable hash of target segments; stored in run records for resume.

`target_segments` — desired segment list (`name`, `range_start`, `range_end`, `kind`).

`attached_segments` — current catalog segments.

`operations` — planned steps: `keep`, `create`, `reshape`, `drop`.

`gaps` — same structure as audit gaps on attached tail.

`hot_buckets` — buckets exceeding heat threshold inside active window.

Use `changed: false` to skip apply when only verifying drift.

### Operation actions

`keep` — segment already matches target.

`create` — new child attach.

`reshape` — bound or name change; may move rows.

`drop` — detach or drop child (retention or layout).

## RunSummary (apply / run!)

`schema_version` — `"1.0"`.

`tables` — array of per-table metrics objects.

`errors` — string messages; run raises `RunFailed` if non-empty (with default `continue_on_error`).

Per-table metrics (`RunMetrics#to_h`):

`table_name` — parent.

`duration_ms` — elapsed milliseconds.

`plan_signature` — signature applied (null if skipped early).

`rows_moved` — rows relocated by maintenance.

`skipped` — boolean.

`skip_reason` — `lock_not_acquired`, etc.

## Run record table

When `run_record_enabled`, PostgreSQL table `partition_gardener_run_records` stores:

`table_name` — parent.

`phase` — rebalance phase checkpoint.

`plan_signature` — resume when matches current plan.

`staging_row_count` — progress through staging partition.

`updated_at` — last checkpoint time.

Disable globally or per table if you do not want checkpoint storage ([configuration.md](configuration.md)).

## CLI mapping

`audit TABLE` — `PartitionGardener.audit(TABLE)`.

`plan TABLE` — `PartitionGardener.plan(table_name: TABLE)`.

`apply --confirm TABLE` — `PartitionGardener.run!(table_name: TABLE)`.

## Related

- [operations.md](operations.md) — remediation workflows
- [monitoring.md](monitoring.md) — metrics from these fields
- [naming.md](naming.md) — segment names in output

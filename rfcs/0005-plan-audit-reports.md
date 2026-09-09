# RFC 0005: Plan, audit, and run reports

- Feature Name: plan-audit-reports
- Type: Standards Track
- Status: Stable
- Created: 2026-09-09
- Author: Andrei Makarov
- Stakeholders: project maintainers
- Relates: RFC 0001, RFC 0008

## Summary

Specify JSON for `plan`, `audit`, and `RunSummary`. `schema_version` is `"1.0"`. Warning strings, operation actions, and skip reasons are the contract jobs and the CLI print.

## Motivation

Operators parse CLI stdout and store `plan_signature`. Changing a field name or a warning sentence breaks monitors without a numbered RFC.

## Guide-level explanation

`partition_gardener --rails plan events` prints one plan object. `audit events` prints warnings including default row count and gaps. `apply --confirm events` prints a `RunSummary` with per-table `rows_moved` and optional `skip_reason`.

## Reference-level explanation

### Plan

Required keys: `schema_version`, `table_name`, `layout`, `changed`, `plan_signature`, `target_segments`, `attached_segments`, `operations`, `gaps`, `hot_buckets`. Additional properties are forbidden. Segment objects have `name`, `range_start`, `range_end`, `kind`. Operation `action` is `keep`, `create`, `reshape`, or `drop`. `changed` is true when operations would mutate catalog or move rows. Gap objects have `message` and optional `range_start` / `range_end`. Schema: `docs/schemas/plan_report.schema.json`.

### Audit

Required: `table_name`, `partitioned`, `default_row_count`, `attached_child_count`, `horizon_days`, `gaps`, `warnings`. Horizon warning when `horizon_days` is below 30. Child-count warning when attached children exceed 200. Warning sentences MUST stay in this catalog:

- `{table} is not a partitioned table`
- `default partition {name} has {n} rows`
- `default partition {name} is missing`
- `partition horizon is {d} days ahead (below 30)`
- `attached child count is {n} (high catalog pressure)`
- `partition gap: uncovered range between {a} and {b} ({from}..{to})`
- `partition gap: no attached tail partition extends to MAXVALUE`
- `child {name} is missing column {columns} from parent {table}`

### RunSummary

Required: `schema_version`, `tables`, `errors`. Per-table metrics: `table_name`, `duration_ms`, `plan_signature`, `rows_moved`, `skipped`, `skip_reason`. Known `skip_reason` values: `lock_not_acquired`, `not_partitioned`, `maintenance_backend_pg_partman`. `run!` raises `RunFailed` when `errors` is non-empty. `continue_on_error` true (default) collects later tables then raises. False raises on the first table error.

### Fail modes

CLI `--all` wraps many plans or audits under `schema_version` plus `tables`. Several registry rows for one parent wrap under `parent_table_name` plus `tables`. Those envelopes are part of the CLI contract (RFC 0008), not the single-table plan schema.

## Implementation notes

`Audit::SCHEMA_VERSION`, `PlanReport::SCHEMA_VERSION`, `RunMetrics#to_h`.

## Registrar

`PartitionGardener.plan`, `PartitionGardener.audit`, `PartitionGardener.run!`, `RunFailed`.

## Drawbacks

Frozen warning strings make wording changes a new RFC. Envelope shapes for `--all` are not in the single-table JSON Schema file.

## Rationale and alternatives

A const `schema_version` lets consumers reject unknown documents. Rejected: free-form log lines as the only audit output.

## Prior art

JSON Schema for plan reports. pg_partman has no machine-readable plan JSON.

## Unresolved questions

Whether `_future` starting after `active_end` should change the MAXVALUE gap text (RFC 0002).

## Future possibilities

A JSON Schema file for audit and RunSummary. Adding `schema_version` 1.1 fields with a new RFC.

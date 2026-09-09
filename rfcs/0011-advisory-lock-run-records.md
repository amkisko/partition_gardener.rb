# RFC 0011: Advisory lock and run records

- Feature Name: advisory-lock-run-records
- Type: Standards Track
- Status: Stable
- Created: 2026-09-09
- Author: Andrei Makarov
- Stakeholders: project maintainers
- Relates: RFC 0005, RFC 0010

## Summary

Specify the Postgres advisory lock that serializes `run!` per table, and the optional run-record row used to resume a matching plan.

## Motivation

Two apply processes on the same parent would attach overlapping children or double-move rows. A lock miss must skip, not raise, so a cron overlap is visible in `RunSummary`.

## Guide-level explanation

The first `apply --confirm events` holds `pg_try_advisory_xact_lock(hashtext('partition_gardener'), hashtext('events'))` for the transaction. A second apply in another session skips `events` with `skip_reason` `lock_not_acquired`. With `run_record_enabled`, a crash mid-rebalance stores `plan_signature` and staging counts so the next matching plan continues.

## Reference-level explanation

Namespace: `hashtext('partition_gardener'), hashtext(table_name)`. Modes: `:transaction` (default) uses `pg_try_advisory_xact_lock`; `:session` uses `pg_try_advisory_lock` and MUST unlock on the same connection after the table finishes.

A miss MUST skip that table, set `skip_reason` `lock_not_acquired`, and MUST NOT raise out of `run!`.

Table `partition_gardener_run_records` columns: `table_name`, `phase`, `plan_signature`, `staging_row_count`, `updated_at`. Resume only when `plan_signature` matches the current plan (RFC 0005). `run_record_enabled` false skips persistence.

### Fail modes

Lock acquire false is a skip, not an error in `errors`. A session-mode process that dies without unlock holds the lock until the backend exits. Missing run-record table when enabled is a run error.

## Implementation notes

`lib/partition_gardener/advisory_lock.rb`. Skip in `PartitionGardener.run!`. Store: `lib/partition_gardener/sql_run_record_store.rb`.

## Registrar

Lock keys `partition_gardener` plus `table_name`. Skip reason `lock_not_acquired`. Table `partition_gardener_run_records`. `run_record_enabled`.

## Drawbacks

`hashtext` collisions across table names are rare but possible. Session mode depends on connection lifetime.

## Rationale and alternatives

Skip-on-miss keeps overlapping crons from failing the job. Rejected: waiting for the lock, which can deadlock a deploy. Rejected: Redis locks, which would not share the database transaction.

## Prior art

PostgreSQL advisory locks. Sidekiq unique jobs (different store).

## Unresolved questions

Whether `--all` should take a registry-wide lock in addition to per-table locks.

## Future possibilities

A `force` unlock operator command. Storing phase names as an enum RFC.

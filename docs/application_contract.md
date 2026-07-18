# Application contract

How host applications should behave around partitioned tables: queries, writes, maintenance side effects, bulk load, and replicas. For UI scoping and aggregate snapshots see [partition_landscape.md](partition_landscape.md). For operator runbooks see [operations.md](operations.md).

## Query and write basics

- Hot-path reads and writes include the partition key in plain predicates (no wrappers on the key column).
- `conflict_key` columns match the parent unique index; updates and deletes use `query_constraints` when the logical id is not globally unique ([partition_landscape.md](partition_landscape.md#rails-application-contract)).
- Inserts supply a routable partition key value so rows land in named children, not only in `default`.
- When only a logical id or parent reference is available, resolve a routable key or bounded window from denormalized columns, parent timestamps, or request context before querying ([partition_landscape.md](partition_landscape.md#routing-hints-when-the-key-is-not-in-hand)).

## During maintenance (row moves)

Maintenance runs move rows in batches keyed by `(partition_key, conflict_key)`:

- Moves are delete-from-source, insert-into-target within transactions; logical row identity is preserved when `conflict_key` is stable.
- Row-level triggers and callbacks fire per batch; prefer idempotent side effects or defer heavy work to jobs keyed by `conflict_key`.
- Counter caches and Rails `counter_cache` on associations may drift during moves; use snapshots or reconcile after maintenance ([partition_landscape.md](partition_landscape.md#aggregates-totals-and-snapshots)).
- Outbox and change-data-capture streams may emit move pairs; consumers should treat `(id, partition_key)` as identity.

After a run with high `rows_moved`, schedule snapshot recompute for affected buckets and watch replica lag.

## Insert routing failures

Row in `default` — key outside attached bounds or horizon lag. Application response: fix key; gardener drains default on next run.

PostgreSQL routing error — no child accepts key. Application response: `apply` to extend horizon; never silence without ops review.

Duplicate key across children — overlapping manual DDL. Application response: stop writes; `plan` / `apply`; remove overlapping attach.

Applications should not catch routing errors and retry without the partition key.

## Bulk import and backfill

- Chunk `COPY` or `insert_all` by bucket window within partition bounds (month, week, day).
- Set partition key explicitly on every row; do not rely on defaults that omit the key.
- Run imports during low traffic or against a shadow table during cutover ([cutover.md](cutover.md)).
- Disable or throttle per-row callbacks on mass load; run bucket snapshot recompute after import completes.

## Read replicas

- Row moves generate write load on the primary; replicas may lag during large `rows_moved` nights.
- Do not run reporting aggregates on replicas that must be strictly current during maintenance windows; use snapshots or primary with bounded windows.
- Logical replication of partitioned parents replicates to the parent; child layout is visible on subscribers. Coordinate major layout changes with replication monitoring.

## Foreign keys and references

PostgreSQL limits foreign keys referencing partitioned tables and FKs across partition boundaries. Prefer:

- Application-level integrity for cross-table references into partitioned facts.
- Composite references that include the partition key when FKs are required.
- Document any FK from partitioned child to dimension table in migration reviews.

Gardener does not add or remove FKs during maintenance.

## Sharded applications

Compose Rails shard routing with per-shard partition filters:

```ruby
ApplicationRecord.connected_to(shard: :tenant_a) do
  Event.in_window(month_range).where(workspace_id: workspace.id)
end
```

Maintenance runs per shard; registry JSON may differ per shard only if layouts differ (unusual).

## Admin and operator surfaces

- Default filters: current month or selected tenant, not all history.
- Global id search is an advanced, slow path; require date or tenant hint.
- Export flows chunk by bucket; show progress per period.
- Totals read from snapshot tables with `computed_at`, not live `SUM` across all children or a stale materialized view over the full fact table ([partition_landscape.md](partition_landscape.md#materialized-views)).

## Testing expectations

See [host_testing.md](host_testing.md) for CI registry fixtures and integration smoke tests.

## Related

- [partition_landscape.md](partition_landscape.md) — pruning, routing hints, UI, snapshots
- [cutover.md](cutover.md) — backfill and switch
- [naming.md](naming.md) — child table names

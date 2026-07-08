# Cutover and migration playbook

Move a live non-partitioned table to declarative partitioning with minimal downtime. Creation DDL uses pg_party or SQL ([pg_party_recipe.md](pg_party_recipe.md)); runtime layout uses Partition Gardener after switch.

## Prerequisites

- Composite unique index including the partition key, matching `conflict_key` ([partition_landscape.md](partition_landscape.md)).
- Registry entry chosen (typically `sliding_window_monthly`; see [decision_flow.md](decision_flow.md)).
- Maintenance job scheduled or CLI access for the first `run!` after cutover.
- Staging environment with production-shaped data and the same registry.

## Phase 1: Creation (no traffic switch)

1. Create shadow parent `p_events` (or your naming convention) with `PARTITION BY RANGE` on the partition key.
2. Create `p_events_default` and minimal premake (current month and next month).
3. Add indexes on the parent (unique on `conflict_key` columns).
4. Do not rename production `events` yet.

See [pg_party_recipe.md](pg_party_recipe.md) for a minimal migration outline.

## Phase 2: Backfill

1. Copy historical rows into `p_events` in batches keyed by partition window (month or bucket).
2. Throttle batch size to protect production I/O; use the same `conflict_key` for idempotent upserts.
3. Compare counts per month between source and shadow (`compare_table_counts` in hot-switch concern).
4. Run application read-only queries against shadow in staging to validate pruning and scopes.

Backfill window for hot-switch delta sync defaults to roughly three months before and after `today` at switch time; extend backfill if older rows must exist before switch.

For cross-database copies (production → staging, or a second cluster during migration), [pgsync](https://github.com/ankane/pgsync) can move filtered subsets with `where` clauses and `--in-batches` on append-only history. Gardener does not run pgsync; schedule it outside `run!` windows so loads do not fight nightly layout work.

## Phase 3: Hot switch

Use `PartitionGardener::Migration::HotSwitchConcern` in a migration:

```ruby
class PartitionEventsHotSwitch < ActiveRecord::Migration[8.0]
  include PartitionGardener::Migration::HotSwitchConcern

  HOT_SWITCH_CONFIG = {
    current_table: "events",
    partitioned_table: "p_events",
    partition_key_column: "occurred_on",
    conflict_key: %w[id occurred_on],
    swap_lock_timeout: "5s", # optional; nil disables; default is 5s when omitted
    partition_config: PartitionGardener::Registry.hot_switch_partition_config("events")
  }.freeze

  def up
    add_write_block_trigger("events") # optional: quiesce writes during final sync
    wait_for_active_transactions("events")
    sync_delta_data
    analyze_shadow_partitions!
    ensure_future_partitions_exist(months_ahead: 1)
    hot_switch_tables
    sync_delta_data(swapped: true) # optional: catch rows on events_old if write-block was skipped
  end
end
```

Switch sequence (inside `hot_switch_tables`):

1. `SET LOCAL lock_timeout` when `swap_lock_timeout` is set (default `5s`).
2. Rename live `events` → `events_old`.
3. Rename `p_events` → `events`.
4. Rename child partitions to match new parent prefix.
5. Repoint serial/identity sequences to the live table (`ALTER SEQUENCE ... OWNED BY`).
6. Remove write-block trigger from `events_old`.

`months_ahead: 1` at switch is enough; gardener extends the sliding window nightly.

`analyze_shadow_partitions!` runs `ANALYZE` on each shadow child and parent before swap. `sync_delta_data` accepts `source_table`, `target_table`, `swapped: true` (post-swap catch-up from `events_old`), `sleep_seconds` between batches, and `batch_size`.

## Cutover comparison: pgslice

[pgslice](https://github.com/ankane/pgslice) solves the same cutover problem with a CLI: `prep` → `add_partitions` → `fill` → `analyze` → `swap`, then optional `fill --swapped` for rows that landed on the retired table after the first fill. Gardener's `HotSwitchConcern` covers the swap phase in a Rails migration, plus live-delta sync and optional write quiesce.

### Step comparison

Shadow parent — pgslice uses `visits_intermediate` (`LIKE` + `PARTITION BY RANGE`); Gardener uses `p_events` (pg_party or SQL creation).

Premake children — pgslice `add_partitions --intermediate`; Gardener `ensure_future_partitions_exist`.

Copy rows — pgslice `fill` in id batches within partition bounds; Gardener Phase 2 backfill plus `sync_delta_data` (UPSERT, partition-key window).

Statistics — pgslice `analyze` on each child and parent; Gardener `analyze_shadow_partitions!` before swap and `analyze_after_rebalance` on first `run!`.

Atomic rename — pgslice renames `visits` → `visits_retired`, intermediate → `visits`; Gardener renames `events` → `events_old`, `p_events` → `events`, and children.

Catch-up after rename — pgslice `fill --swapped` from retired to live; Gardener `sync_delta_data(swapped: true)` or write-block trigger before swap.

Rollback drill — pgslice `unswap`; Gardener `hot_unswitch_tables`.

The rename swap uses the same low-downtime pattern: metadata (table name) flips in one transaction; the app keeps querying `events` without code changes.

### Gardener extras for live cutover

Delta sync before switch — `sync_delta_data` upserts only rows in a sliding date window that are missing or stale on the shadow table (`updated_at` comparison). pgslice's first `fill` is id-batch oriented and assumes a numeric primary key; catch-up after rename is a separate `fill --swapped` pass.

Write quiesce — optional `add_write_block_trigger` plus `wait_for_active_transactions` narrow the race between last sync and rename.

Registry handoff — after swap, `Registry` plus nightly `run!` own runtime maintenance. pgslice stops at swap and expects a cron `add_partitions` you must later disable ([tooling_split.md](tooling_split.md)).

### Hot-switch config reference

`swap_lock_timeout` — default `"5s"`. Sets `SET LOCAL lock_timeout` in swap/unswitch transaction; `nil` disables.

`sync_batch_size` — default `PartitionGardener::MOVE_BATCH_SIZE`. Rows per `sync_delta_data` batch.

`sync_stale_column` — default `"updated_at"`. Stale-row detection for upserts.

Sequence repointing uses `pg_get_serial_sequence` per column; custom sequence names are supported.

### Using pgslice for creation, Gardener for switch

Valid hybrid when you do not use pg_party:

1. `pgslice prep` / `add_partitions` / `fill` / `analyze` on the shadow tree.
2. Register the table in Gardener before switch.
3. Replace `pgslice swap` with a migration that calls `analyze_shadow_partitions!`, `sync_delta_data`, `ensure_future_partitions_exist`, and `hot_switch_tables`.
4. Disable pgslice `add_partitions` cron; run Gardener nightly.

Do not run pgslice premake and Gardener `run!` on the same parent without `maintenance_backend` coordination.

## Phase 4: After cutover

1. Register `events` in `PartitionGardener::Registry` if not already loaded.
2. `bundle exec partition_gardener --rails audit events` — target default row count trending to zero.
3. `bundle exec partition_gardener --rails plan events` — review first layout diff.
4. `bundle exec partition_gardener --rails apply --confirm events` or wait for nightly job.
5. Recompute bucket snapshots for dashboard totals if you use rollup tables ([partition_landscape.md](partition_landscape.md#aggregates-totals-and-snapshots)).
6. Drop `events_old` only after retention policy, legal review, and verified row counts.

## Rollback

Before dropping `events_old`:

1. Stop maintenance job for `events` or set maintenance window.
2. Call `hot_unswitch_tables` in a migration, or reverse renames manually: `events` → `p_events`, `events_old` → `events`.
3. Re-point application if any code assumed partitioned shape.
4. Document registry removal to avoid gardener acting on the wrong parent.

Rollback after `events_old` is dropped requires restore from backup; treat drop as irreversible.

## Template upgrades

### premake_monthly → sliding_window_monthly

1. Register new template; `plan` to preview tail and default drain.
2. Run `apply` during low traffic; expect `rows_moved` from default and tail reshape.
3. Remove legacy cron premake jobs.

### Changing bucket (monthly → weekly)

Treat as a new partitioning scheme: new parent or full reload into a new tree. Gardener does not rewrite archive naming in place. Plan a new shadow table, backfill, and hot switch.

### Composite trees

Native PostgreSQL sub-partition DDL is your migration responsibility. Register each gardener-maintained node separately ([partition_landscape.md](partition_landscape.md#composite-trees)). Creation migration attaches the full tree; gardener plans each registered parent.

## Cutover checklist

- [ ] `conflict_key` matches parent unique index
- [ ] Shadow backfill complete; counts match per bucket
- [ ] `ensure_future_partitions_exist(months_ahead: 1)` succeeds
- [ ] Hot switch migration applied
- [ ] Sequences owned by live table, not `events_old` (`hot_switch_tables` repoints serial columns; verify after switch)
- [ ] Registry loaded in all app processes
- [ ] First `audit`: default rows acceptable or draining
- [ ] First `apply` or nightly job succeeded
- [ ] Application scopes and UI use partition key on hot paths
- [ ] Snapshot rollups invalidated or recomputed for affected buckets
- [ ] `events_old` drop scheduled with backup verification

## Related

- [pg_party_recipe.md](pg_party_recipe.md) — creation DDL sketch
- [operations.md](operations.md) — post-cutover incidents
- [host_testing.md](host_testing.md) — CI and staging for host apps
- [tooling_split.md](tooling_split.md) — do not double-maintain with partman

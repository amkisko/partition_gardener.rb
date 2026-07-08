# Related Postgres tooling (ankane)

Partition Gardener owns runtime layout maintenance on declarative partitions. [Andrew Kane's Postgres tools](https://github.com/ankane) solve adjacent problems: observability, indexing, data copy, and one-time partition cutover. None of them replace Gardener's sliding window, heat splits, default drain, or incremental tail rebalance.

Use this page with [tooling_split.md](tooling_split.md) (creation vs runtime maintenance vs extension) and [partition_landscape.md](partition_landscape.md) (templates and out-of-scope).

## At a glance

[PgHero](https://github.com/ankane/pghero) — database performance dashboard. Low overlap with Gardener (whole-database observability, not partition layout). Pair with nightly `audit` / `run!`.

[Dexter](https://github.com/ankane/dexter) — automatic indexes from query workload. No overlap on partition bounds; use after large rebalance or new hot children.

[pgsync](https://github.com/ankane/pgsync) — copy Postgres data between databases. Overlap on cutover backfill and staging refresh, not nightly maintenance. Use for staging refresh and offline backfill phases.

[pgslice](https://github.com/ankane/pgslice) — one-time partition prep, fill, swap. High overlap on creation; low on runtime maintenance. Create with pgslice before Gardener; do not run both as maintainers.

## PgHero

PgHero is a performance dashboard for Postgres: slow queries, index usage, space, connections, vacuum statistics, and replication lag. It ships as a Rails engine, Docker image, or Linux package.

### Usefulness with Gardener

High as complementary observability, not as a partition maintainer.

Gardener already exposes layout-specific signals: `audit`, `plan`, default row count, horizon days, attached child count, and `RunSummary` metrics ([monitoring.md](monitoring.md)). PgHero answers different questions: which queries are slow globally, which indexes are unused, whether autovacuum is keeping up, and whether connection pools are saturated.

Pair them when:

- A table shows high `rows_moved` or long `run.duration_ms` and you need query-level context (`pg_stat_statements`).
- Partition count or catalog warnings fire and you want bloat or sequential-scan visibility across the database.
- Operators want one dashboard for database observability and a second view (Gardener audit JSON or metrics) for partition layout.

### What to learn

Focused scope — one problem (Postgres observability), multiple install paths (Rails engine, Docker, package). Gardener also ships as gem plus CLI plus optional railtie.

Related-project cross-links — each README points to Dexter, pgsync, pgslice. Gardener should keep creation tools (pg_party) and runtime maintenance tools (pg_partman, Gardener) linked the same way; this document is part of that.

Actionable defaults — PgHero highlights issues operators recognize without reading planner internals. Gardener's `audit` warning catalog ([audit_reference.md](audit_reference.md)) should stay similarly concrete.

### What not to take

Do not fold general slow-query analysis into Gardener. Keep partition layout maintenance as the gem boundary ([partition_landscape.md](partition_landscape.md) out-of-scope).

## Dexter

Dexter recommends and optionally creates indexes from `pg_stat_statements`, live activity, or log files. It uses HypoPG to test hypothetical indexes before `CREATE INDEX CONCURRENTLY`.

### Usefulness with Gardener

Medium as a follow-up tool after partition work, not during layout planning.

Partition maintenance changes where data lives and how many child tables exist. New hot-month splits and tail rebalances can shift which indexes matter. Dexter helps when:

- A rebalance moved a large fraction of rows and query plans regressed.
- New dedicated hot partitions need indexes copied from the parent.
- Heat-driven splits increased partition count and planners started choosing different paths.

Gardener does not analyze `pg_stat_statements` or create indexes. Dexter does not create partition bounds, drain default, or detach archive children.

### What to learn

Safe-by-default execution — Dexter finds indexes first; `--create` is explicit. Gardener's `plan` / `dry_run` and retention dry-run (`retention_apply: false`) follow the same operator contract.

Noise filters — `--min-calls` and `--min-time` avoid indexing one-off queries. Gardener's heatmap threshold (`split_row_threshold`) follows the same idea: act only when signal is strong enough.

Table allow/deny lists — `--include` / `--exclude` for write-heavy tables. Gardener's per-table registry and `maintenance_backend` skip list serve a similar ownership boundary.

### What not to take

Index recommendation inside Gardener would duplicate Dexter and blur the hot path. Document "run Dexter after major layout change" in [operations.md](operations.md) if operators need a checklist, not a new dependency.

## pgsync

pgsync copies data from one Postgres database to another: parallel table transfer, row filters, schema-first sync, sensitive-data rules, and batch mode for large append-only tables.

### Usefulness with Gardener

High for staging and migration data movement; none for nightly partition maintenance.

Overlap with Gardener appears only in cutover and cross-environment copy:

Phase 2 backfill ([cutover.md](cutover.md)) — copy historical months into a shadow partitioned parent before hot switch. pgsync can move batches with `where` clauses and `--in-batches` on id-keyed tables when you are not using Gardener's built-in delta sync.

Staging refresh ([host_testing.md](host_testing.md)) — sync a subset of production partitions into staging so `plan` and `run!` see realistic shapes.

Cross-database fill — pgslice's README explicitly sends readers to pgsync for syncing between databases during migration.

pgsync does not add future months, split hot buckets, or detach archives. Running pgsync on a production parent while Gardener `run!` is active risks fighting over the same rows unless scopes are disjoint and schedules are coordinated.

### What to learn

Safety rails — default destination is localhost unless `to_safe: true`. Worth echoing in Gardener docs: dry-run plan before apply, retention dry-run, advisory lock skip instead of blocking production.

data_rules — redact emails and secrets on the way out of production. Relevant when exporting partition dumps for compliance ([retention.md](retention.md)) even though Gardener does not implement sync.

Foreign-key ordering — `--defer-constraints` and `--jobs 1` for ordered loads. Cutover backfill order (archive months before current) is the partition-shaped version of the same problem.

### What not to take

Gardener should not become a database-to-database sync tool. Keep `HotSwitchConcern` and cursor rebalance for in-place migration; point operators at pgsync for staging clones and offline copies.

## pgslice

pgslice is the closest cousin: CLI workflow to partition an existing table — `prep` (intermediate parent), `add_partitions`, `fill`, `analyze`, `swap`, then ongoing `add_partitions` via cron. Archive is manual: `pg_dump` partition child, `DROP TABLE`.

### Usefulness with Gardener

High for creation; intentionally redundant for runtime maintenance if both run uncoordinated.

Create partitioned parent — pgslice `prep` plus intermediate table; Gardener pg_party, SQL, or migration ([pg_party_recipe.md](pg_party_recipe.md)).

Premake future bounds — pgslice `add_partitions --future N` on cron; Gardener sliding window future zone or `premake_monthly` bridge.

Move rows into children — pgslice `fill` in id batches; Gardener tail rebalance, default drain, hot-switch delta.

Cutover — pgslice `swap` renames intermediate to live; Gardener `HotSwitchConcern`: `hot_switch_tables`, `hot_unswitch_tables` ([cutover.md](cutover.md)).

Archive old data — pgslice operator script dump plus drop child; Gardener `retention_months` plus detach/drop ([retention.md](retention.md)).

Hot month inside window — not supported in pgslice; Gardener heatmap plus dedicated hot partitions.

Default partition drain — not a first-class pgslice workflow; mandatory last phase in Gardener.

Recommended split (same pattern as [tooling_split.md](tooling_split.md)):

1. Use pgslice (or pg_party plus SQL) once to create or convert the table.
2. Register with Gardener and set `maintenance_backend: :gardener`.
3. Stop pgslice `add_partitions` cron for that table — Gardener owns premake and archive layout.

If you keep pgslice cron for premake only, treat it like pg_partman: register `maintenance_backend: :hybrid_layout_only` or `:pg_partman` semantics so Gardener does not create duplicate bounds.

### Hot-switch API (Gardener)

Rails migrations include `PartitionGardener::Migration::HotSwitchConcern`:

`hot_switch_tables` — pgslice equivalent `swap`. Rename live to `_old`, shadow to live, children, sequences.

`hot_unswitch_tables` — pgslice equivalent `unswap`. Reverse swap for drills or rollback.

`analyze_shadow_partitions!` — pgslice equivalent `analyze`. `ANALYZE` shadow children and parent before swap.

`sync_delta_data` — pgslice equivalent `fill`. UPSERT delta rows into shadow (pre-swap).

`sync_delta_data(swapped: true)` — pgslice equivalent `fill --swapped`. Catch-up from `_old` into live after swap.

`swap_lock_timeout` config — pgslice `lock_timeout` in swap. Fail fast on blocked renames (default `5s`).

See [cutover.md](cutover.md) for the full migration example.

### What to learn

Intermediate plus swap — low-downtime rename pattern matches `hot_switch_tables` / `hot_unswitch_tables`. Teams using pgslice for creation can hand off to Gardener at swap ([cutover.md](cutover.md)).

`--dry-run` prints SQL — operators see exact DDL before execution. Gardener `plan` JSON and CLI `plan --pretty` serve a similar trust model for nightly layout; hot-switch migrations execute SQL directly — use staging drills and `compare_table_counts` for cutover.

Partition metadata in comments — pgslice stores `column`, `period`, `version` on the intermediate table comment. Gardener could optionally record layout version in run records for upgrade audits (future idea, not required today).

Missing-partition monitor query — pgslice documents a `pg_class` check for expected future child names. Gardener `horizon_days` and audit warnings cover missing bounds — see [audit_reference.md](audit_reference.md).

App guidance — pgslice README stresses filters on the partition key for pruning. Gardener already covers this in [partition_landscape.md](partition_landscape.md); keep one canonical pruning section.

### What not to take

pgslice's fill loop is id-batch oriented for monolithic to partitioned copy. Gardener's incremental tail rebalance and default drain are ongoing lifecycle concerns — different algorithms, different schedules. Do not merge pgslice fill into Gardener.

## Suggested operator stack

Typical production stack for a Rails app with time-series partitions:

1. Creation — pg_party or pgslice `prep` / `swap` (or Gardener hot-switch migration).
2. Runtime maintenance — Partition Gardener nightly `run!` plus `audit` cron.
3. Observe — PgHero (or existing APM) plus Gardener metrics ([monitoring.md](monitoring.md)).
4. Indexes — Dexter or manual review after large rebalance or template upgrade.
5. Staging — pgsync from production subset; run `plan` before enabling `run!` in staging.

## Optional follow-ups

Concrete patterns for future work. None are required for current releases.

Handoff checklist in [cutover.md](cutover.md): after pgslice swap, register template and disable pgslice cron.

Optional audit warning when expected future child name is missing (pgslice-style monitor), if not already covered by `horizon_days`.

Operations runbook: run `ANALYZE` on touched children after large `rows_moved` (pgslice `analyze` step; Gardener `analyze_after_rebalance` is the hook).

Cross-link [Dexter](https://github.com/ankane/dexter) in [operations.md](operations.md) when `split_row_threshold` fires often — new hot children may need index review.

## Source

- [PgHero](https://github.com/ankane/pghero)
- [Dexter](https://github.com/ankane/dexter)
- [pgsync](https://github.com/ankane/pgsync)
- [pgslice](https://github.com/ankane/pgslice)
- In-repo: [tooling_split.md](tooling_split.md), [cutover.md](cutover.md), [monitoring.md](monitoring.md), [partition_landscape.md](partition_landscape.md)

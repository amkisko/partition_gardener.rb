# Partition landscape

Partition Gardener targets PostgreSQL native declarative partitioning with gardener-owned maintenance plans. This page maps industry patterns to what the gem implements, documents experimental layouts, and lists what belongs outside the gem.

## Implemented templates

sliding_window_monthly — layout sliding_window, bucket month, reliability recommended. Default time-series on a date or timestamp column.

sliding_window_daily — layout sliding_window, bucket day, reliability legacy. High-volume telemetry with short retention.

sliding_window_weekly — layout sliding_window, bucket week, reliability legacy. Weekly rollups or compliance windows.

sliding_window_quarterly — layout sliding_window, bucket quarter, reliability legacy. Finance or reporting quarters.

calendar_year — layout calendar_year, bucket year, reliability legacy. Long-lived yearly archives.

rolling_current_monthly — layout rolling_current, bucket month, reliability experimental. One wide current child, no heat splits inside the active window.

premake_monthly — layout premake_monthly, bucket month, reliability legacy. Bridge from cron premake; migrate to sliding window.

integer_window — layout integer_window, reliability legacy. Monotonic bigint keys with id-band pruning.

list_split — layout list_split, reliability legacy. Small stable enum or tenant discriminator.

hash_branches — layout hash_branches, reliability experimental. Even fan-out on a hash key.

composite_list_hash — layout composite, reliability legacy. LIST parent with HASH sub-trees per branch.

composite_list_range — layout composite, reliability experimental. LIST parent with RANGE sliding-window sub-trees.

list_range — layout composite, reliability experimental. Alias for composite_list_range.

composite_range_hash — layout composite, reliability experimental. RANGE parent with HASH child tables.

composite_range_list — layout composite, reliability experimental. RANGE parent with LIST child tables.

Register with `Registry.register_template(:sliding_window_monthly, ...)` or `Registry.register(Templates.sliding_window_monthly(...))`.

## Rolling current

`rolling_current_monthly` keeps the three-area sliding window but disables heat splits inside the active window. Archive months still detach one bucket at a time. Prefer `sliding_window_monthly` unless you explicitly want a single wide current partition.

## Composite trees

Gardener maintains each registered table in a composite tree separately:

- LIST parent (`list_split`) when `parent_mode: :list`
- RANGE parent (`sliding_window` or `calendar_year`) when `parent_mode: :range`
- Child tables named `parent_branch` with layout from the branch entry (`hash_branches`, `sliding_window`, or `list_split`)

Native PostgreSQL sub-partition DDL (one attached tree) is your migration responsibility. Gardener plans and rebalances each registered node.

## Rails horizontal sharding

Rails ships horizontal sharding in Active Record (since 6.0, expanded in 8.0). You declare shard databases in `database.yml`, connect models with `connects_to shards:`, route requests with `connected_to(shard:)`, and run cross-shard work with `connected_to_all_shards` (Rails 8+).

That is a different layer from PostgreSQL declarative partitioning:

- Rails sharding splits rows across database servers with the same schema (tenant or capacity isolation).
- Gardener splits rows across child tables on one PostgreSQL server (time or key bounds, retention, default drain).

They compose. A sharded Rails app can still partition `events` on each shard for retention and tail layout. Gardener maintenance runs against one connection at a time; point `connection_resolver` at the active shard connection, or loop shards in a job:

```ruby
ShardRecord.connected_to_all_shards do
  PartitionGardener.run!(table_name: "events")
end
```

The default railtie uses `ActiveRecord::Base.connection`. Sharded models should set `connection_resolver` to their shard connection, or run maintenance inside `connected_to(shard:)` for each shard.

Choose Rails sharding when the bottleneck is total row volume or tenant isolation across servers. Choose Gardener templates when the bottleneck is partition catalog size, retention, or hot-month splits inside one database.

## Composite keys and partition pruning

Partitioning only speeds up queries when PostgreSQL can skip child tables. That is partition pruning: the planner uses partition bounds and your `WHERE` clause to exclude partitions that cannot hold matching rows. Without pruning, one large scan becomes many smaller scans and latency often gets worse.

Longer narrative and Rails context: [Tiny story PostgreSQL partitioning and Rails](https://amkisko.github.io/posts/20260306112539_tiny_story_postgresql_partitioning_and_rails.html).

### PostgreSQL rules

PostgreSQL enforces `UNIQUE` and `PRIMARY KEY` per partition, not globally on the parent. Every unique constraint on a partitioned table must include the partition key columns. A typical OLTP shape is composite primary key `(id, occurred_on)` when partitioning by `occurred_on`, or `(id, tenant_id)` when partitioning by `tenant_id`.

Pick the partition key from real query patterns. Community guidance (production write-ups and [PostgreSQL table partitioning](https://www.postgresql.org/docs/current/ddl-partitioning.html)) converges on: the column that appears in most hot `WHERE` clauses should drive `PARTITION BY`. If no single dimension dominates, pruning will not help the queries that omit it.

Filters must expose the partition key plainly:

- Prefer range predicates: `occurred_on >= '2026-03-01' AND occurred_on < '2026-04-01'`
- Avoid wrappers on the key: `DATE(occurred_on)`, `date_trunc('month', occurred_on)`, or casts that hide the bound from the planner
- Watch `OR` across disjoint ranges; the planner may scan every child
- Joins that only filter on `id` without the partition key often cannot prune until runtime, and sometimes not at all

Verify with `EXPLAIN (ANALYZE, BUFFERS)` on production-shaped queries. Pruning-capable plans show `Append` with only the relevant children, or `Subplans Removed: N` when runtime pruning applies. Sequential scans on every child mean the application contract is missing the partition key.

`enable_partition_pruning` is on by default. Pruning is driven by partition bounds, not by indexes on the key; indexes still matter inside each child for point lookups.

### Rails application contract

Active Record queries the parent table; models do not need to know child names. Performance still depends on scopes and APIs that carry the partition key.

When the database primary key is composite only because of partitioning, but `id` remains the application identifier:

```ruby
class Event < ApplicationRecord
  self.primary_key = :id
  query_constraints :id, :occurred_on
end
```

`query_constraints` (Rails 7.1+) adds listed columns to `UPDATE` and `DELETE` `WHERE` clauses so writes can prune. It does not add the partition key to `SELECT` lookups: `Event.find(id)` may still scan all partitions unless `id` is globally unique and the planner can prove a single child.

For reads, encode the contract in scopes used by hot paths:

```ruby
scope :in_window, ->(range) { where(occurred_on: range.begin...range.end) }
```

Inserts must supply routable partition key values (`Event.create!(occurred_on: ...)`) so rows land in named children, not only in `default`.

If you register `partition_key_column: "created_at::date"`, keep application filters on that expression or use a generated column the planner can reason about.

### Gardener `conflict_key`

Registry `conflict_key` must match a parent unique index and should include the partition key, for example `%w[id occurred_on]`. Gardener uses it for idempotent keyset moves during default drain and tail rebalance. The same composite shape that satisfies PostgreSQL uniqueness is what lets maintenance target one partition without cross-child ambiguity.

### Sharded apps

With Rails `connects_to` sharding, carry both signals on hot paths: shard routing first (`connected_to(shard:)`), then partition key filters inside that shard. Losing either one pushes the system toward broad scans. Partition Gardener on each shard does not change that query contract.

### UI and product surfaces

Partition boundaries are an application contract, not only a database detail. Screens and APIs should make the same separation key visible to people so routine work stays inside one prune-friendly slice. User-facing copy should describe periods, accounts, or branches in product language, not partitions, shards, or child tables.

Time-partitioned data (monthly sliding window):

- Default list and calendar views to the current month or a short rolling window, not all history
- Month or week navigation that maps one-to-one to bucket boundaries (calendar pager, period tabs)
- Require or strongly default a date range before loading large tables; block unbounded browse behind an explicit export or report flow
- Date range pickers that emit half-open ranges (`from` inclusive, `to` exclusive) matching server scopes
- Cursor and infinite scroll keyed by `(occurred_on, id)` or equivalent so pagination stays ordered within a window
- Create and edit forms that set the event date explicitly; avoid backdating without a visible date field

List- or tenant-partitioned data:

- Workspace, region, or branch selector as the first step when categories are stable LIST keys
- Scoped navigation so cross-category search is a deliberate action, not the default index
- Per-tenant dashboards that never load sibling tenants in one query

Sharded Rails apps:

- Account or org context in the URL or session before data loads (`connected_to(shard:)` matches what the user already chose)
- Avoid global admin search across shards; offer shard-scoped search with optional slow cross-shard report

APIs and exports:

- List endpoints accept `from` / `to` (or `period`) and reject or paginate narrowly when missing
- Bulk export jobs chunked by month or tenant with progress per chunk
- GraphQL connections and REST `page` tokens should carry the partition dimension in the cursor when the key is temporal

Anti-patterns:

- Homepage table of millions of rows with only sort-by-id and page number
- Single global search box that queries by id across all time
- "All workspaces" aggregate view on hot OLTP paths without a reporting pipeline

When adding a screen, ask whether a typical click produces a query that includes the same key you partition on. If not, change the interaction before adding indexes.

### Aggregates, totals, and snapshots

Dashboard totals, KPI cards, and cross-period rollups should not scan every partition on each page load. Treat them as snapshots: precomputed rows stored outside the hot OLTP path, refreshed in background, with explicit drift control.

Services that run maintenance only when indicators show need (instead of nightly `run!`) should treat snapshots as mandatory on hot paths, not a later optimization. Deferred layout work is viable only when request threads never depend on live aggregates across the full retention window. Design snapshots first, then choose indicator-driven maintenance cadence ([decision_flow.md](decision_flow.md#maintenance-cadence), [background_job.md](background_job.md#schedule)).

Why this pairs with partitioning:

- A `COUNT(*)` or `SUM(amount)` over all history touches every child; latency grows with retention even when list views are scoped
- Wide reporting queries belong off the request thread; snapshots make the UI fast and predictable
- Detached or dropped archive partitions still need totals for closed periods; snapshots survive layout changes

Snapshot shape:

- Key snapshots by the same dimensions you partition on: `(period, tenant_id, metric)` or `(calendar_month, workspace_id)`
- One row per bucket per grain (day, month, quarter), not one global total unless the product truly needs it
- Store `computed_at`, optional `source_watermark` (max `updated_at` or max id seen in source), and `version` for cache busting
- Keep snapshots in a normal table or a dedicated rollup schema; they are not partition children of the fact table

Prefer a regular rollup table over a materialized view when bucket keys, drift checks, and incremental updates matter. Materialized views are a poor stand-in for partition-shaped aggregates; see [Materialized views](#materialized-views) below.

Background recalculation:

- Incremental: on each write to the fact table, adjust the open bucket snapshot (current month, active tenant) in the same transaction or via an outbox job
- Periodic full recompute: nightly or weekly job walks one bucket at a time (`WHERE occurred_on >= ... AND occurred_on < ...`) and replaces snapshot rows for closed periods
- Chunk jobs by partition bucket so each job prunes to one or few children; never one job that aggregates all shards and all time without bounds
- On sharded apps, compute per shard first, then merge shard snapshots in a coordinator job if the product needs a global number

Drift control:

- Reconciliation job compares snapshot totals to a fresh `COUNT` / `SUM` over the same bucket window on a schedule; record `drift` and `last_checked_at`
- Alert when drift exceeds a threshold or when `computed_at` is older than SLA for the period (stale snapshot)
- After Gardener moves rows (default drain, tail rebalance), rerun bucket recompute for affected windows; moves change row location but not logical totals if keys are stable
- UI shows "as of" time on totals; optional subtle stale state when reconciliation is behind
- Idempotent recompute: upsert snapshot rows by bucket key so retries do not double-count

Anti-patterns:

- Live `SELECT SUM(...)` across all partitions on the homepage
- Caching unbounded aggregate queries in Redis without bucket keys or TTL tied to period close
- Assuming ORM counter caches on the parent model stay correct when rows move between children during maintenance

Gardener does not maintain application snapshots; it only changes partition layout. Application jobs own rollup freshness and drift checks.

### Materialized views

PostgreSQL does not support declarative partitioning on materialized views. You cannot attach `PARTITION BY RANGE`, `LIST`, or `HASH` to a materialized view, run `ATTACH PARTITION` / `DETACH PARTITION` on one, or add `CHECK` constraints that enable constraint exclusion on child slices. Partition Gardener operates on declarative partitioned tables only; it does not plan, audit, or refresh materialized views.

What still works:

- Create a materialized view whose defining query reads from a partitioned fact table. Partition pruning may reduce work during refresh when the query carries plain predicates on the partition key, but `REFRESH MATERIALIZED VIEW` (PostgreSQL 18 and earlier) still replaces the entire stored result each time.
- `REFRESH MATERIALIZED VIEW CONCURRENTLY` avoids blocking readers but refreshes the whole view and requires a unique index on plain columns covering all rows.

Manual sharding pattern (common workaround):

- One materialized view per time slice, each defined with a bounded `WHERE` on the source key.
- A regular `VIEW` with `UNION ALL` over those materialized views as the query surface.

Limits of that pattern:

- No partition pruning across the union; a filter like `WHERE sale_date = '2026-04-15'` typically scans every child materialized view unless the application queries a specific child by name.
- No `CHECK` constraints on materialized views, so the planner cannot prove row bounds per child.
- Lifecycle is manual: new period means new materialized view, alter the union view, manage dependencies, and schedule per-slice refresh jobs.
- pg_partman and Gardener do not maintain materialized views.

Partial refresh on the horizon:

- PostgreSQL 19 may add `REFRESH MATERIALIZED VIEW ... WHERE predicate` for predicate-scoped refresh. That narrows refresh cost; it does not make materialized views first-class partition citizens (no attach/detach, no gardener-style layout).

Recommended pairing with Gardener:

- Fast dashboard totals with drift control — bucket-keyed rollup table (optionally range-partitioned by period)
- Drop old periods with retention — partitioned fact table plus Gardener; snapshots keyed by closed bucket survive detach
- Stale-OK full recompute of one report — single materialized view over a bounded source query
- Independent refresh per month at very large scale — multiple materialized views plus union view, with application routing to children; accept no cross-union pruning

For hot paths next to indicator-driven maintenance, use snapshot tables with `computed_at` and reconciliation ([Aggregates, totals, and snapshots](#aggregates-totals-and-snapshots)), not a monolithic materialized view over all history.

After Gardener moves rows between children, refresh or recompute any materialized view or snapshot that aggregates affected buckets. Gardener does not trigger those jobs.

### Common pitfalls (what teams report)

- Admin search by `id` only on a time-partitioned table scans every month until the key encodes time or lookups include `occurred_on`
- Reporting queries over wide date ranges intentionally touch many children; that is correct behavior, not a pruning bug
- Partition count in the thousands increases planner overhead even when pruning works; Gardener sliding window keeps the active catalog bounded
- Relying on `default` without monitoring; Gardener drains default last, but application inserts that never match bounds still accumulate there
- Assuming `includes` / `preload` on associations will prune parent partitions when the join does not constrain the partition key
- Product UI that encourages unbounded browse (all-time lists, global id search) while the table is partitioned by time or tenant
- Dashboard totals computed live across all partitions instead of served from bucket-keyed snapshots with background refresh and drift checks
- Treating one large materialized view as a partitioned rollup; refresh cost grows with retention and Gardener row moves do not update it automatically
- Expecting `UNION ALL` over per-month materialized views to prune like declarative partitions; query the child materialized view directly or use a rollup table

## Out of scope

Delegate these to other tools or extensions; Gardener does not embed them.

### Materialized views

Declarative partitioning and Gardener maintenance apply to tables, not materialized views. See [Materialized views](partition_landscape.md#materialized-views) for manual multi-view patterns, refresh limits, and when to use rollup tables instead.

### ankane Postgres tools

PgHero (observe), Dexter (indexes), pgsync (database copy), and pgslice (one-time partition prep and swap) address different layers than nightly partition maintenance. See [related_postgres_tooling.md](related_postgres_tooling.md) for pairing and overlap.

### pg_partman

Use `maintenance_backend: :pg_partman` or `:hybrid_layout_only` when partman owns premake and detach. Gardener can still plan layout-only diffs in hybrid mode.

### TimescaleDB hypertables

Hypertables use chunk policies and compression, not declarative RANGE children. Use Timescale maintenance for time-series at scale.

### Citus distributed tables

Citus distributes tables across worker nodes inside PostgreSQL with its own shard metadata and rebalance tooling. That is neither Rails `connects_to` sharding nor native declarative partitioning on a single instance. Gardener does not drive Citus shard placement.

### UUIDv7 and encoded-time keys

Time-ordered UUID primary keys are increasingly common. Partitioning on `date_trunc` of a timestamp column remains the recommended Gardener path. For UUID-native range strategies, use pg_partman 5.2+ or custom DDL; Gardener does not parse UUID time components today.

## Choosing a bucket

General application events — start with sliding_window_monthly, active_months 12.

Metrics or logs under 90 days — sliding_window_daily.

Weekly compliance exports — sliding_window_weekly.

Quarterly financial partitions — sliding_window_quarterly.

Multi-year cold storage — calendar_year.

Multi-tenant rows across database servers — Rails `connects_to` shards; optionally partition per shard with Gardener.

## Source

Industry intervals use the same units as pg_partman `part_config.partition_interval` and PostgreSQL `date_trunc`. Composite naming follows native `PARTITION BY LIST` and `PARTITION BY RANGE` sub-partition trees described in PostgreSQL documentation.

Further reading:

- [Tiny story PostgreSQL partitioning and Rails](https://amkisko.github.io/posts/20260306112539_tiny_story_postgresql_partitioning_and_rails.html)
- [PostgreSQL: Table partitioning](https://www.postgresql.org/docs/current/ddl-partitioning.html)
- [PostgreSQL: Materialized views](https://www.postgresql.org/docs/current/rules-materializedviews.html)
- [PostgreSQL: REFRESH MATERIALIZED VIEW](https://www.postgresql.org/docs/current/sql-refreshmaterializedview.html)
- [Rails Guides: Multiple databases (horizontal sharding)](https://guides.rubyonrails.org/active_record_multiple_databases.html)
- [GitLab: Partitioned tables and composite primary keys](https://docs.gitlab.com/development/database/partitioning/)
- [Aha!: Partitioning a large table in PostgreSQL with Rails](https://www.aha.io/engineering/articles/partitioning-a-large-table-in-postgresql-with-rails)

Operations and migration docs in this repository:

- [operations.md](operations.md) — runbook
- [cutover.md](cutover.md) — hot-switch playbook
- [application_contract.md](application_contract.md) — host app behavior
- [monitoring.md](monitoring.md) — metrics and alerts
- [retention.md](retention.md) — archive detach and drop
- [audit_reference.md](audit_reference.md) — audit and plan catalog

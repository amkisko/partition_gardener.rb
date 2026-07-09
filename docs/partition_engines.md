# Partition engines and portable patterns

Partition Gardener implements runtime maintenance for PostgreSQL native declarative partitioning. The gem is PostgreSQL-specific today: catalog introspection, attach and detach DDL, advisory locks, and pg_partman integration all assume one PostgreSQL connection.

The problems Gardener solves are not PostgreSQL-only. Large tables split by time or category need the same operational invariants on every engine that supports partition-shaped lifecycle: bounded catalog size, headroom for future inserts, retention without bulk delete, and a single maintainer that reconciles layout against policy. This page maps those portable patterns to other database engines, states where Gardener's current implementation applies as-is, and where teams should borrow the design without expecting this gem to run unchanged.

Use this page with [partition_landscape.md](partition_landscape.md) (templates and PostgreSQL scope), [decision_flow.md](decision_flow.md) (when to partition), and [tooling_split.md](tooling_split.md) (creation vs runtime maintenance).

## Portable patterns Gardener encodes

These concepts are engine-agnostic. Gardener's registry, planner, audit, and plan JSON express them for PostgreSQL; another engine would need its own DDL adapter but can reuse the same operator contract.

Sliding window with three areas — archive holds finalized buckets before the active window. Current holds a bounded active span with optional heat-driven splits. Future is one open-ended tail. Default (where the engine supports it) is a safety net that must trend empty.

Premake and horizon — upper bound of the latest non-default child stays ahead of maximum insert keys. Missing future bounds route inserts to default or fail inserts depending on engine.

Default drain last — rows that landed in the catch-all partition move into named children before archive work. Maintenance treats default as mandatory final phase.

Heat splits inside current — hot buckets inside the active window get dedicated children; gap fillers cover non-hot buckets so bounds stay contiguous.

Keyset rebalance — row moves use composite cursor on partition key plus conflict key, not offset pagination. Idempotent batches delete from source after insert.

Retention by whole child — old periods leave via detach or drop of a partition child, not `DELETE` across the parent. Snapshot and rollup jobs must refresh affected buckets after moves ([partition_landscape.md](partition_landscape.md#aggregates-totals-and-snapshots)).

Single maintainer per parent — one owner per table per run; overlapping premake cron and layout repair is a configuration error ([tooling_split.md](tooling_split.md)).

Plan before apply — dry-run plan, audit warnings, indicator thresholds, and `retention_apply: false` preview mirror operator trust models on any engine.

Hot-switch cutover — shadow partitioned parent, minimal premake, atomic rename, then runtime maintenance owns the window ([cutover.md](cutover.md)).

Template registry — sliding_window_monthly, list_split, hash_branches, and composite trees are layout policies independent of PostgreSQL syntax.

Reliability invariants from [decision_flow.md](decision_flow.md#reliability-invariants) transfer: partition key in unique constraints, no overlapping bounds, one owner, retention by child removal, analyze after large reshapes where statistics drive pruning.

## At a glance by engine

PostgreSQL — full Gardener target. Declarative RANGE, LIST, HASH, composite sub-partition trees, default partition, ATTACH/DETACH, CONCURRENTLY detach (14+).

YugabyteDB YSQL — high pattern overlap, gem not validated. PostgreSQL-compatible declarative partitioning (RANGE, LIST, HASH), default partition, attach and detach. Distributed tablets and geo-partitioning add placement concerns Gardener does not model. Likely needs connection adapter and staging tests; core planner concepts map.

MySQL and MariaDB — partial pattern overlap, no Gardener today. RANGE, LIST, HASH, KEY, and subpartitioning. No PostgreSQL-style default partition; out-of-range inserts error. Premake via `ADD PARTITION` / `REORGANIZE PARTITION`. Retention via `DROP PARTITION` or `EXCHANGE PARTITION` with staging tables. Sliding window and hot-switch map to exchange-based workflows, not attach rebalance.

Oracle — partial overlap, no Gardener today. Interval partitioning auto-creates future range partitions on insert (built-in premake). Rolling window still needs scheduled `DROP PARTITION` / `TRUNCATE PARTITION`. Composite LIST-RANGE and interval-hash match Gardener composite templates conceptually. Heat splits and default drain have no direct analogue.

SQL Server (MSSQL) — partial overlap, no Gardener today. Partition function plus scheme; sliding window via SWITCH, SPLIT, MERGE, NEXT USED. Hot-switch and retention map closely; no default partition. Azure SQL Database and managed instance use the same verbs. See [SQL Server (MSSQL)](#sql-server-mssql) below.

IBM Db2 — high overlap for detach/attach semantics, no Gardener today. RANGE partitioning with `ALTER TABLE ... DETACH PARTITION ... INTO` and `ATTACH PARTITION`; roll-in/roll-out matches PostgreSQL archive story. Async detach task and SET INTEGRITY differ from PostgreSQL.

Amazon Aurora MySQL — same as MySQL partitioning limits and EXCHANGE workflow; cluster storage is opaque. Gardener patterns apply at the MySQL layer.

CockroachDB — low overlap for Gardener detach/drop model. Partitions are logical subdivisions of one physical table, not separately droppable children. No bulk drop by partition; repartition or row-level TTL for expiry. Range and list partitioning help geo zones and pruning, not Gardener-style archive detach. Borrow audit indicators and application contract; implement retention with TTL or batched DELETE.

ClickHouse — low overlap for row rebalance; high overlap for retention shape. `PARTITION BY` on MergeTree; TTL and `ALTER TABLE ... DROP PARTITION` for lifecycle. Premake is implicit as data arrives into new parts. No cross-partition row moves like PostgreSQL default drain. Align partition granularity with TTL ([ClickHouse TTL guidance](https://clickhouse.com/docs/guides/developer/ttl)). Gardener's sliding window is policy documentation; engine TTL does the work.

TimescaleDB — out of scope ([partition_landscape.md](partition_landscape.md#timescaledb-hypertables)). Hypertable chunks and compression policies replace declarative children.

Citus — out of scope ([partition_landscape.md](partition_landscape.md#citus-distributed-tables)). Distribution across workers is not declarative partitioning on one instance.

Snowflake, BigQuery, Redshift — warehouse partitioning and clustering are metadata for pruning and storage layout, not attachable child tables. Borrow horizon, retention, and snapshot patterns; maintenance is DDL or TTL at the warehouse layer, not Gardener.

SQLite — no native table partitioning. Application-level shard tables or archive tables only.

## PostgreSQL and YugabyteDB YSQL

### PostgreSQL

Gardener's reference engine. Templates in [partition_landscape.md](partition_landscape.md#implemented-templates) map directly to `PARTITION BY` methods. `Executor` issues `CREATE TABLE ... PARTITION OF`, `ATTACH PARTITION`, `DETACH PARTITION`, and keyset moves between children.

Extension and tool boundaries stay as documented: pg_partman for plain premake ([tooling_split.md](tooling_split.md)), Timescale and Citus out of scope, ankane tools for adjacent layers ([related_postgres_tooling.md](related_postgres_tooling.md)).

### YugabyteDB YSQL

YSQL implements PostgreSQL-style declarative partitioning: `PARTITION BY RANGE | LIST | HASH`, `CREATE TABLE ... PARTITION OF`, default partition, attach, and detach ([YugabyteDB table partitioning](https://docs.yugabyte.com/stable/explore/ysql-language-features/advanced-features/partitions/), [partition by time](https://docs.yugabyte.com/stable/develop/data-modeling/common-patterns/timeseries/partitioning-by-time/)).

Patterns that transfer from Gardener without semantic change:

- Monthly or daily range windows with default catch-all
- Retention by `DROP TABLE` on detached or attached partition children
- Composite primary key including partition key for uniqueness and pruning
- List-then-range composite trees for geo or branch plus time
- Application contract: filters on partition key, UI scoped to period or tenant ([partition_landscape.md](partition_landscape.md#rails-application-contract))

Gardener-specific gaps on YugabyteDB:

- No shipped `YugabyteConnection` or CI matrix against YSQL
- Catalog queries target `pg_catalog` shapes; verify `pg_inherits` and `pg_get_expr` bound parsing on target versions
- Each child is also sharded into tablets; detach/drop affects DocDB placement — plan replication and zone policies outside Gardener
- Foreign keys referencing partitioned parents remain constrained ([YugabyteDB FK discussion](https://dev.to/yugabyte/foreign-keys-referencing-partitioned-tables-in-yugabytedb-26pn)); same composite-key rule as PostgreSQL

Practical path: treat Gardener as a design reference and operator checklist first. Pilot on YSQL with `connection_resolver` pointed at a cluster and compare `plan` output to manual `information_schema` / catalog inspection before any production `run!`.

## MySQL and MariaDB

MySQL partitioning is declared at `CREATE TABLE` with RANGE, LIST, HASH, or KEY; subpartitioning adds a second level ([MySQL partitioning types](https://dev.mysql.com/doc/refman/8.4/en/partitioning-types.html)).

### What matches Gardener patterns

Range by date or timestamp — maps to `sliding_window_monthly`, `sliding_window_daily`, and calendar year templates. Retention via `ALTER TABLE ... DROP PARTITION` for old months.

List by stable category — maps to `list_split` and LIST parent in composite templates.

Hash modulus — maps to `hash_branches`; changing modulus is a major migration on every engine.

Composite RANGE + HASH or RANGE + KEY — maps to `composite_list_range` and `composite_range_hash` conceptually via subpartitioning.

Hot-switch — `ALTER TABLE ... EXCHANGE PARTITION ... WITH TABLE` is metadata-heavy row swap, analogous to pgslice swap and Gardener `hot_switch_tables` ([related_postgres_tooling.md](related_postgres_tooling.md#pgslice)).

### What differs

No default partition — inserts outside defined bounds fail with error 1526 rather than routing to `_default`. Gardener's default-drain-last phase has no target; premake and horizon are stricter operational requirements.

Child identity — partitions are numbered (`p0`, `p1`, ...) or named in DDL; not separate freely named tables until exchange workflows. Gardener's `{table}_current` / `{table}_future` naming ([naming.md](naming.md)) would be custom DDL, not native attach slots.

Layout repair — adding a range uses `ADD PARTITION` or `REORGANIZE PARTITION`, not PostgreSQL `ATTACH` of a pre-filled child. Row moves for backfill often use `EXCHANGE PARTITION` with a staging table rather than keyset `INSERT ... DELETE` across attached children.

Unique constraints — partition key must be part of every unique index ([MySQL constraints](https://dev.mysql.com/doc/refman/8.4/en/partitioning-limitations.html)); same rule as PostgreSQL.

### How Gardener helps without running on MySQL

Use Gardener's JSON plan and audit shape as a specification for a MySQL maintainer: same registry fields (`partition_key_column`, `active_months`, `retention_months`, `split_row_threshold`), same indicators (horizon, heat, gap warnings), different executor issuing `ADD PARTITION`, `DROP PARTITION`, and `EXCHANGE`.

Recommended MySQL sliding window (conceptual):

1. Premake next month with `ADD PARTITION` before the first day of the new month.
2. Keep partition count bounded; `DROP PARTITION` for months older than retention.
3. For cutover from non-partitioned table, load staging table and `EXCHANGE PARTITION` per month ([exchange partitions](https://dev.mysql.com/doc/refman/8.4/en/partitioning-management-exchange.html)).
4. Enforce application filters on partition key; no default safety net.

4. Enforce application filters on partition key; no default safety net.

## IBM Db2

Db2 table partitioning splits rows across data partitions by RANGE on one or more columns ([table partitioning](https://www.ibm.com/docs/en/db2/11.1.0?topic=tables-table-partitioning)). Roll-in and roll-out use `ATTACH PARTITION` and `DETACH PARTITION` on `ALTER TABLE` ([detaching partitions](https://www.ibm.com/docs/en/db2/11.5.x?topic=ranges-detaching-data-partitions), [rolling scenarios](https://www.ibm.com/docs/en/db2/11.1.0?topic=apt-scenarios-rolling-in-rolling-out-partitioned-table-data)).

### What matches Gardener patterns

Detach for retention — `ALTER TABLE stock DETACH PARTITION dec01 INTO stock_drop` turns a range into a standalone table without row movement; drop or archive the standalone table. Same intent as PostgreSQL `DETACH` then `DROP` ([retention.md](retention.md)).

Attach for premake — roll new ranges in from standalone tables or empty attached partitions waiting for `SET INTEGRITY`.

Sliding window — detach oldest month, attach new month; bounded partition count matches Gardener archive plus future discipline.

No overlapping ranges — attach boundaries must not overlap existing ranges; gap detection and horizon warnings from Gardener audit translate directly.

### What differs

SET INTEGRITY — attached partitions may require `SET INTEGRITY` before fully visible; Gardener has no equivalent phase.

Async detach — detach completes in phases; queries under some isolation levels continue during detach.

Distribution — `DISTRIBUTE BY HASH` plus `PARTITION BY RANGE` combines Db2 DPF with table partitioning; Gardener does not model database partition groups.

No PostgreSQL default partition name — overflow behavior is attach discipline and range design, not `_default` drain.

### How Gardener helps on Db2

Db2 is the strongest non-PostgreSQL candidate after YugabyteDB YSQL for a detach/attach executor port. Registry, planner layout, retention months, and plan JSON map with DDL swapped to Db2 `ATTACH`/`DETACH`. Validate `SET INTEGRITY` and async detach in integration specs before production `apply`.

## Oracle

Oracle offers range, list, hash, reference, interval, and composite partitioning ([partitioning concepts](https://docs.oracle.com/en/database/oracle/oracle-database/26/vldbg/partition-concepts.html)).

### What matches Gardener patterns

Interval partitioning — automatic creation of range partitions when data exceeds the transition point. This is built-in premake; Gardener `premake_monthly` and future-zone repair are partly redundant for forward bounds.

Range and composite — monthly archive plus list branch maps to Gardener templates at the policy level.

Retention — `ALTER TABLE ... DROP PARTITION` / `TRUNCATE PARTITION` for closed intervals; aligns with [retention.md](retention.md) detach-then-drop semantics when partitions are materialized.

Rolling window — still requires scheduled drop of old intervals; interval partitioning does not remove the need for retention automation ([Oracle maintenance](https://docs.oracle.com/en/database/oracle/oracle-database/21/vldbg/maintenance-partition-tables-indexes.html)).

### What differs

No PostgreSQL default partition — routing semantics differ; "overflow" behavior is interval extension, not a `_default` child.

Heat splits inside current — Oracle subpartition add on materialized intervals is possible but not the same as Gardener heatmap-driven dedicated months inside a sliding current zone.

Global indexes — partition maintenance can mark global index partitions unusable unless `UPDATE INDEXES` is used; Gardener's per-child local index story does not cover Oracle global index rebuild policy.

### How Gardener helps on Oracle

Borrow the decision flow and indicator set: when interval partitioning is enough, run drop-only retention jobs; when composite LIST-RANGE or manual range is used, document three-area layout in registry JSON even if Oracle DDL is hand-written PL/SQL.

Teams often combine interval premake with a scheduled procedure to drop partitions older than N months — Gardener's `retention_months` and audit warnings are the checklist for that job.

## SQL Server (MSSQL)

SQL Server, Azure SQL Database, and Azure SQL Managed Instance share the same partition model: a partition function defines boundary values, a partition scheme maps partition numbers to filegroups, and the table references both at create time ([partitioned tables and indexes](https://learn.microsoft.com/en-us/sql/relational-databases/partitions/partitioned-tables-and-indexes?view=sql-server-ver17)).

Partition Gardener does not run on SQL Server today. The overlap with Gardener is among the strongest of any non-PostgreSQL engine for sliding-window retention and hot-switch cutover, because `SWITCH` is metadata-only like PostgreSQL attach/detach and pgslice swap.

### Objects and catalog

Partition function — maps partition key values to partition numbers (`CREATE PARTITION FUNCTION ... AS RANGE LEFT | RIGHT FOR VALUES (...)`).

Partition scheme — maps partition numbers to filegroups (`CREATE PARTITION SCHEME ... AS PARTITION function_name TO (...)`).

Partitioned heap or clustered index — `CREATE TABLE ... ON scheme(column)`; nonclustered indexes inherit the table scheme unless overridden.

Staging tables — for sliding window and cutover, aligned nonpartitioned tables (same columns, indexes, constraints) receive switched-out data.

Audit queries — `sys.partition_functions`, `sys.partition_schemes`, `sys.partition_range_values`, `sys.partitions`, and `$PARTITION.function_name(column)` for row routing checks ([$PARTITION](https://learn.microsoft.com/en-us/sql/t-sql/functions/partition-transact-sql?view=sql-server-ver17)).

RANGE LEFT vs RIGHT — controls which side of a boundary value belongs to which partition. For datetime keys, wrong choice splits a calendar day across partitions. Pick once at function creation and mirror it in maintenance scripts ([sliding window notes](https://weblogs.sqlteam.com/dang/2008/08/30/sliding-window-table-partitioning/)).

### Gardener phase mapping

Gardener sliding_window_monthly intent maps to SQL Server operations as follows.

Premake / future zone — read max boundary from `sys.partition_range_values`; while horizon is short, run `ALTER PARTITION SCHEME ... NEXT USED filegroup` then `ALTER PARTITION FUNCTION ... SPLIT RANGE (new_boundary)`. SPLIT on an empty trailing partition is fast (metadata only). This is Gardener `horizon_days` and future-tail repair.

Archive / retention — `ALTER TABLE Orders SWITCH PARTITION partition_number TO Orders_Archive` (aligned staging), then `TRUNCATE TABLE Orders_Archive` or export and drop staging, then `ALTER PARTITION FUNCTION ... MERGE RANGE (old_boundary)` on the vacated low boundary. MERGE requires the merged partition empty. Matches [retention.md](retention.md) detach-then-drop without PostgreSQL child table names.

Hot-switch cutover — load shadow partitioned table or staging tables per month, then `SWITCH` partitions into the live partitioned table, or switch whole aligned tables during migration. Closest analogue to Gardener `HotSwitchConcern` and pgslice swap ([cutover.md](cutover.md), [related_postgres_tooling.md](related_postgres_tooling.md#pgslice)).

Default drain — no PostgreSQL-style DEFAULT partition. Out-of-range inserts fail unless the function includes a catch-all boundary. Premake discipline is mandatory; there is no `_default` safety net to drain last.

Heat splits inside current — not native. SQL Server does not add mid-window monthly children inside one partition without SPLIT that affects function metadata. High-volume months are usually separate filegroups, compression, or archive switching, not Gardener heatmap splits.

Keyset rebalance — not attach-style row moves. Data moves via `SWITCH` to aligned tables or insert-select in staging, then switch back.

### SWITCH requirements

`ALTER TABLE ... SWITCH PARTITION` succeeds only when source and target are aligned:

- Same column count, order, types, and nullability
- Matching clustered and nonclustered indexes on the same columns
- Same check constraints and indexed views where applicable
- Target empty for switch-in, or switch-out rules satisfied

Misaligned staging is the main cutover failure mode. Gardener's hot-switch checklist (analyze, delta sync, count compare) applies verbatim; only DDL differs.

### Sliding window maintenance loop (monthly)

Typical automated loop after each month closes (RIGHT-range example):

1. Ensure trailing empty partition exists (SPLIT last range if needed).
2. SWITCH out the oldest populated partition to `Orders_Stage_Archive`.
3. Archive or truncate staging; drop exported data per policy.
4. MERGE the vacated low boundary (both sides must be empty per your LEFT/RIGHT strategy).
5. SPLIT to extend the high end for future months (NEXT USED + SPLIT).
6. Update statistics on affected partitions.

Reuse Gardener registry fields as procedure parameters: `retention_months` drives which boundary MERGEs, `active_months` bounds how many populated partitions stay attached, horizon maps to how far ahead SPLIT runs.

Microsoft documents automatic sliding-window patterns in [partition strategies](https://learn.microsoft.com/en-us/previous-versions/sql/sql-server-2008/cc719702(v=sql.100)) and community write-ups ([mssqltips sliding window](https://www.mssqltips.com/sqlservertip/5296/implementation-of-sliding-window-partitioning-in-sql-server-to-purge-data/)).

### Azure SQL Database and managed instance

Same T-SQL partition function, scheme, SWITCH, SPLIT, and MERGE on Azure SQL Database and Azure SQL Managed Instance. Filegroup mapping still exists; elastic pools and hyperscale change IO and size limits, not the maintenance verbs.

Differences from on-prem:

- Partition count and table size limits follow service tier docs; plan partition count below tier caps (historically 15,000 partitions per table on enterprise-class limits; verify current docs for your SKU).
- No local filegroup tuning on some offerings; scheme may map many partitions to `PRIMARY` or tier-specific storage.
- Long-running SPLIT/MERGE still benefits from empty partitions; schedule during low traffic like Gardener indicator-driven maintenance.

Borrow Gardener audit indicators: max boundary vs today plus horizon, oldest boundary vs retention cutoff, row counts per `$PARTITION` before MERGE.

### Rails and Active Record

Rails apps on SQL Server use the SQL Server adapter; models query the parent table name. Partition pruning depends on `WHERE` on the partition key in scopes, same contract as PostgreSQL ([partition_landscape.md](partition_landscape.md#rails-application-contract)).

Composite primary keys including the partition key apply when uniqueness is enforced per partition. `query_constraints` (Rails 7.1+) helps targeted updates when the logical key spans partition key plus id.

Gardener railtie and CLI do not apply. Run partition maintenance via SQL Agent job or application scheduler calling a stored procedure; keep one maintainer per table.

### What Gardener provides without a port

- Registry JSON as policy document (`partition_key_column`, `retention_months`, `active_months`, `bucket: :month`)
- Plan vocabulary: archive, premake, retention, horizon
- Audit warning catalog adapted to `$PARTITION` row counts and boundary gaps
- Cutover playbook structure from [cutover.md](cutover.md)
- UI and snapshot discipline from [partition_landscape.md](partition_landscape.md)

A future `SqlServerConnection` adapter would read `sys.partition_*` instead of `pg_inherits`, emit SPLIT/MERGE/SWITCH instead of ATTACH/DETACH, and use `sp_getapplock` instead of PostgreSQL advisory locks.


## CockroachDB

CockroachDB partitions are logical: one physical table subdivided for zone configs and pruning, not separately droppable tables ([table partitioning](https://www.cockroachlabs.com/docs/stable/partitioning)).

### What matches Gardener patterns

Range by date for archival placement — move cold ranges to cheaper nodes via zone configs; same product goal as archive zone in sliding window.

List for geo — maps to `list_split` policy for region or tenant keys.

Application contract — filters on partition key for pruning; UI scoped to region or period ([partition_landscape.md](partition_landscape.md#ui-and-product-surfaces)).

Audit indicators — default row count is not applicable; horizon becomes "repartition needed before insert range exceeds defined bounds".

### What differs

No `DETACH PARTITION` / `DROP PARTITION` for bulk removal — drop data with row-level TTL, changefeed plus batched `DELETE`, or repartition the table ([archival partitioning blog](https://blog.cloudneutral.se/archival-partitioning-with-cockroachdb), [row-level TTL](https://www.cockroachlabs.com/docs/stable/row-level-ttl)).

Repartition instead of attach — changing bounds is `ALTER TABLE ... PARTITION BY` or `PARTITION BY NOTHING`, not Gardener tail rebalance.

Default drain — no default child; inserts outside defined ranges error or require repartition.

### How Gardener helps on CockroachDB

Gardener is a poor fit as a runtime gem. Use decision_flow and partition_landscape for when to partition, snapshot discipline, and UI contract. Implement retention with TTL jobs and monitor `sql.ttl` job metrics, not Gardener `run!`.

## ClickHouse

ClickHouse uses `PARTITION BY` expression on MergeTree family engines; partitions are sets of parts on disk ([partitions](https://clickhouse.com/docs/partitions), [delete old data](https://clickhouse.com/docs/faq/operations/delete-old-data)).

### What matches Gardener patterns

Monthly or daily partition key — `toYYYYMM(date)` or `toStartOfMonth(date)` matches `sliding_window_monthly` and daily templates.

Retention — `ALTER TABLE ... DROP PARTITION` or TTL when partition key aligns with TTL expression; whole-part drop is the analog of Gardener archive detach/drop.

Horizon — less critical; new partitions appear as parts when data arrives. Policy focus shifts to TTL and `ttl_only_drop_parts` rather than premake DDL.

### What differs

No row moves between partitions — mutations rewrite parts; no default partition drain or keyset rebalance between children.

Heat splits — not applicable inside one month; scale is vertical merging and part sizing, not extra child tables.

OLTP mixed workload — ClickHouse is analytics-first; Gardener's three-area OLTP layout targets PostgreSQL-style insert routing.

### How Gardener helps on ClickHouse

Use Gardener registry fields as documentation: `retention_months` becomes TTL interval; `bucket: :month` becomes `PARTITION BY toYYYYMM(ts)`. Align TTL granularity with partition expression per ClickHouse guidance. Gardener audit concepts (stale snapshots, unbounded UI queries) still apply ([partition_landscape.md](partition_landscape.md#aggregates-totals-and-snapshots)).

## Warehouses and analytics engines

### Snowflake, BigQuery, Redshift

These systems expose partition columns or clustering keys for pruning and storage billing, not PostgreSQL-style child tables.

Portable from Gardener:

- Partition key choice from query patterns ([decision_flow.md](decision_flow.md))
- Retention policy expressed as months or days of data
- Snapshot tables for dashboard totals instead of scanning all history
- UI defaults to bounded periods

Not portable:

- `plan` / `attach` / `default drain` / advisory lock maintenance loop
- Template registry tied to physical child names

Implement lifecycle in warehouse-native DDL (partition filter on load, table expiration, lifecycle rules) using Gardener docs as the policy spec.

Snowflake — micro-partitions are automatic; `CLUSTER BY` aids pruning. Retention via time travel limits and table-level drop or truncate, not monthly child detach.

BigQuery — ingestion-time or column partitioning on load; partition expiration policies replace Gardener `retention_months`.

Redshift — distribution and sort keys; slice-level layout unlike declarative children. Archive with unload to object storage plus delete, or query via external tables.

### Greenplum and other MPP Postgres forks

Greenplum distributes across segments; declarative partitioning syntax may exist per version but maintenance is entangled with segment distribution. Treat like Citus: Gardener does not own segment placement. Product-specific validation required before any port.

SingleStore — distributed SQL with shard keys plus optional `PARTITION BY`; combine MySQL-style exchange patterns with cluster routing. Gardener registry documents policy; executor would be product-specific.

## Mapping Gardener templates to other engines

sliding_window_monthly — PostgreSQL and YSQL: full. Db2: DETACH/ATTACH monthly RANGE. MySQL: ADD/DROP monthly RANGE. Oracle: interval or range plus drop job. SQL Server: SWITCH/SPLIT/MERGE monthly function. ClickHouse: `PARTITION BY toYYYYMM`. CockroachDB: range partitions plus TTL for drop. Warehouse: partition column or ingestion time.

sliding_window_daily — Same engines with day granularity; ClickHouse `toYYYYMMDD`.

calendar_year — Yearly RANGE or list of years; Oracle interval with year expression; warehouses use year column.

integer_window — PostgreSQL, YSQL, MySQL HASH/RANGE on id bands; SQL Server partition function on id ranges.

list_split — PostgreSQL, YSQL, MySQL LIST, Oracle LIST, CockroachDB list for geo.

hash_branches — PostgreSQL HASH, MySQL KEY/HASH, Oracle hash subpartitions; fixed modulus at DDL everywhere.

composite_list_range / composite_list_hash — PostgreSQL subpartition, MySQL subpartitioning, Oracle composite; not one-shot in CockroachDB without repartition planning.

premake_monthly — PostgreSQL Gardener bridge; Oracle interval supersedes; MySQL and SQL Server need explicit premake scripts; ClickHouse N/A.

rolling_current_monthly — Experimental everywhere; wide single current child risks catalog and pruning tradeoffs Gardener documents for PostgreSQL.

## What a multi-engine future would require

Partition Gardener today splits cleanly into:

Portable core — registry, templates, planner layout math (`DateBucket`, `SlidingWindow`, heat maps), plan diff, audit warning catalog, run records, CLI plan/audit.

Engine adapter — catalog introspection, bound parsing, DDL for create/attach/detach/exchange/split, row move strategy, lock primitive, extension probes (pg_partman equivalent).

A second engine adapter would implement the same `Connection` contract `Executor` expects: quoted identifiers, partition listing, row counts per child, and mutating DDL. PostgreSQL-specific pieces live in `PgConnection`, `Connection` catalog SQL, and `MaintenanceBackend` partman probe.

Minimal expansion order by pattern overlap:

1. YugabyteDB YSQL — validate catalog compatibility and run integration specs against a cluster.
2. IBM Db2 — detach/attach executor; SET INTEGRITY phase after attach.
3. SQL Server — switch/split/merge executor; `sys.partition_*` metadata instead of `pg_inherits`.
4. MySQL — exchange-based executor; no default drain phase.

CockroachDB, ClickHouse, and warehouses need different products (TTL-first or warehouse lifecycle), not a port of attach/detach rebalance.

## Operator checklist when the engine is not PostgreSQL

Keep from Gardener regardless of engine:

- Partition key in all unique constraints and hot-path queries
- One maintainer per table; no overlapping premake crons
- Retention by removing whole partitions or TTL, not unbounded DELETE
- Plan or dry-run before destructive DDL
- Snapshot totals for cross-period aggregates
- UI and APIs default to partition-scoped windows ([partition_landscape.md](partition_landscape.md#ui-and-product-surfaces))
- After large data movement, refresh statistics and dependent rollups

Replace Gardener-specific steps:

- Default drain last — only when the engine has a catch-all partition
- `DETACH CONCURRENTLY` — PostgreSQL 14+ only
- Advisory lock — engine-specific distributed lock or job mutex
- `maintenance_backend: :pg_partman` — PostgreSQL extension only

## Related in this repository

- [partition_landscape.md](partition_landscape.md) — PostgreSQL templates, pruning, out of scope extensions
- [decision_flow.md](decision_flow.md) — whether and how to partition
- [tooling_split.md](tooling_split.md) — creation vs runtime maintenance on PostgreSQL
- [related_postgres_tooling.md](related_postgres_tooling.md) — adjacent Postgres tools
- [retention.md](retention.md) — detach and drop on PostgreSQL
- [naming.md](naming.md) — child naming catalog
- [cutover.md](cutover.md) — hot-switch playbook

## Source

PostgreSQL and portable concepts:

- [PostgreSQL: Table partitioning](https://www.postgresql.org/docs/current/ddl-partitioning.html)
- [Tiny story PostgreSQL partitioning and Rails](https://amkisko.github.io/posts/20260306112539_tiny_story_postgresql_partitioning_and_rails.html)

YugabyteDB:

- [Table partitioning](https://docs.yugabyte.com/stable/explore/ysql-language-features/advanced-features/partitions/)
- [Partition data by time](https://docs.yugabyte.com/stable/develop/data-modeling/common-patterns/timeseries/partitioning-by-time/)
- [YSQL row-level partitioning design](https://github.com/yugabyte/yugabyte-db/blob/master/architecture/design/ysql-row-level-partitioning.md)

MySQL:

- [Partitioning types](https://dev.mysql.com/doc/refman/8.4/en/partitioning-types.html)
- [Exchange partitions](https://dev.mysql.com/doc/refman/8.4/en/partitioning-management-exchange.html)

Oracle:

- [Partitioning concepts](https://docs.oracle.com/en/database/oracle/oracle-database/26/vldbg/partition-concepts.html)
- [Maintenance operations](https://docs.oracle.com/en/database/oracle/oracle-database/21/vldbg/maintenance-partition-tables-indexes.html)

SQL Server:

- [Partitioned tables and indexes](https://learn.microsoft.com/en-us/sql/relational-databases/partitions/partitioned-tables-and-indexes?view=sql-server-ver17)
- [ALTER PARTITION FUNCTION](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-partition-function-transact-sql?view=sql-server-ver17)
- [$PARTITION](https://learn.microsoft.com/en-us/sql/t-sql/functions/partition-transact-sql?view=sql-server-ver17)
- [Sliding window partitioning](https://www.mssqltips.com/sqlservertip/5296/implementation-of-sliding-window-partitioning-in-sql-server-to-purge-data/)

IBM Db2:

- [Table partitioning](https://www.ibm.com/docs/en/db2/11.1.0?topic=tables-table-partitioning)
- [Detaching data partitions](https://www.ibm.com/docs/en/db2/11.5.x?topic=ranges-detaching-data-partitions)
- [Rolling in and rolling out](https://www.ibm.com/docs/en/db2/11.1.0?topic=apt-scenarios-rolling-in-rolling-out-partitioned-table-data)

CockroachDB:

- [Table partitioning](https://www.cockroachlabs.com/docs/stable/partitioning)
- [Row-level TTL](https://www.cockroachlabs.com/docs/stable/row-level-ttl)

ClickHouse:

- [Table partitions](https://clickhouse.com/docs/partitions)
- [TTL guide](https://clickhouse.com/docs/guides/developer/ttl)
- [Delete old data FAQ](https://clickhouse.com/docs/faq/operations/delete-old-data)

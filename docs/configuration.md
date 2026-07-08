# Configuration

Partition Gardener has two configuration layers:

1. Global — `PartitionGardener.configure` in a Rails initializer (or before CLI use)
2. Per-table — entries in `PartitionGardener::Registry` built from `Templates.*` or JSON

Pick layout and maintainer first ([decision_flow.md](decision_flow.md), [tooling_split.md](tooling_split.md)). Use this document as the option reference.

## Global configuration

```ruby
# config/initializers/partition_gardener.rb
PartitionGardener.configure do |config|
  config.notifier = ->(message_or_error, context: {}) {
    Rails.logger.info(message_or_error)
  }
  config.statement_timeout_wrapper = ->(timeout, &block) {
    DatabaseTimeout.statement_timeout(timeout, &block) # host-app helper
  }
  config.today_resolver = -> { Time.zone.today }
  config.continue_on_error = true
  config.advisory_lock_mode = :transaction
  config.run_record_store = PartitionGardener::SqlRunRecordStore.new
end
```

When the gem loads inside Rails, the railtie sets `connection_resolver` and `today_resolver` automatically.

`notifier` (default: no-op proc) — receives errors and info messages with a `context:` hash (`table_name`, `job`, `action`, …).

`connection_resolver` (default: `ActiveRecord::Base.connection` when Rails is loaded, else `PartitionGardener::PgConnection` from `DATABASE_URL`) — database connection for maintenance SQL.

`statement_timeout_wrapper` (default: passthrough) — wraps each table's maintenance in a host timeout (recommended in production).

`today_resolver` (default: `Date.today`) — reference date for archive, current, and future window math.

`schema_name` (default: `"public"`) — schema searched for parent and child partitions.

`continue_on_error` (default: `true`) — when one table fails, continue others; raise `RunFailed` at end with all errors.

`advisory_lock_mode` (default: `:transaction` with Active Record, `:session` with standalone `PgConnection`) — `:transaction` uses `pg_try_advisory_xact_lock`; `:session` uses `pg_try_advisory_lock`.

`analyze_after_rebalance` (default: `false`) — run `ANALYZE` on parent after tail rebalance (global default).

`incremental_rebalance` (default: `true`) — skip unchanged tail partitions when resuming (global default).

`run_record_enabled` (default: `true`) — persist phase checkpoints for resume (global default).

`run_record_store` (default: `SqlRunRecordStore` when a database connection is available, else in-memory) — where rebalance checkpoints are stored.

`strict_maintenance_backend_validation` (default: `false`) — when `true`, raise `MaintenanceBackend::ValidationError` on register if `maintenance_backend` disagrees with `partman.parent_config`; when `false`, notify only.

`retention_detach_concurrently` (default: `false`) — detach dropped archive partitions with `CONCURRENTLY` (global default).

### Advisory locks

Each table run acquires `pg_advisory_lock(hashtext('partition_gardener'), hashtext(table_name))` (or the transaction-scoped variant).

`:transaction` (default with Active Record) — lock is held for one table maintenance transaction. If another worker already holds it, the table is skipped (`lock_not_acquired` in run metrics) and maintenance continues for other tables. Prefer `:session` when a single table run can take many minutes, because `:transaction` keeps one database transaction open for the whole run.

`:session` — lock spans the whole table run across multiple transactions; released in an `ensure` block. Default when the connection resolver returns `PgConnection`.

Do not run two full `run!` jobs against the same table concurrently. Host apps should also limit concurrent maintenance jobs (see [background_job.md](background_job.md)).

### Run records

When a database connection is configured (Active Record or `DATABASE_URL`), `SqlRunRecordStore` creates `partition_gardener_run_records` on first use. Run records let incremental rebalance resume after partial failure. Disable with `config.run_record_enabled = false` or per-table `run_record_enabled: false`.

## Per-table registration

Register one config hash per partitioned parent (composite layouts expand to child configs internally).

```ruby
PartitionGardener::Registry.register_template(
  :sliding_window_monthly,
  table_name: "audits",
  partition_key_column: "created_at::date",
  conflict_key: %w[id created_at],
  active_months: 12,
  move_batch_size: 10_000,
  statement_timeout: 10.minutes,
  retention_months: 24
)

# equivalent two-step form:
# Registry.register(Templates.sliding_window_monthly(...))

# or bulk:
PartitionGardener::Registry.register_all([config_a, config_b])
```

`Registry.register_template` calls the matching `Templates` builder, then `Registry.register`. `Registry.register` normalizes the config, assigns a reliability tier, validates `maintenance_backend` against `partman.part_config`, and replaces any prior entry with the same `table_name`.

### Template builders

`Templates.sliding_window_monthly` — layout `:sliding_window`, bucket `:month`; key option `active_months` (default 12).

`Templates.sliding_window_daily` — bucket `:day`; key option `active_days` (default 90).

`Templates.sliding_window_weekly` — bucket `:week`; key option `active_weeks` (default 52).

`Templates.sliding_window_quarterly` — bucket `:quarter`; key option `active_quarters` (default 8).

`Templates.rolling_current_monthly` — layout `:rolling_current`; monthly sliding window without heat splits.

`Templates.calendar_year` — layout `:calendar_year`; key option `active_years` (default 2).

`Templates.premake_monthly` — layout `:premake_monthly`; key option `premake_months` (default 3).

`Templates.integer_window` — layout `:integer_window`; key options `active_id_lo`, `active_id_width`, `current_band_size`, `archive_band_size`.

`Templates.hash_branches` — layout `:hash_branches`; key option `hash_modulus`.

`Templates.list_split` — layout `:list_split`; key option `branches`.

`Templates.composite_list_hash` — layout `:composite`, `parent_mode: :list`; LIST parent plus HASH branches.

`Templates.composite_list_range` / `Templates.list_range` — LIST parent plus RANGE sliding-window branches.

`Templates.composite_range_hash` — RANGE parent plus HASH child tables.

`Templates.composite_range_list` — RANGE parent plus LIST child tables.

See [partition_landscape.md](partition_landscape.md) for reliability tiers and out-of-scope patterns.

All templates accept shared options passed through to the registry hash:

`partition_key_column` (required) — column or SQL expression used for routing and moves.

`conflict_key` (required) — unique key columns for idempotent batch moves (must match a parent unique index). Include the partition key so the index is valid on partitioned parents and maintenance can target one child; see [partition_landscape.md](partition_landscape.md).

`move_batch_size` (default: `10_000`, constant `MOVE_BATCH_SIZE`) — rows per move batch.

`split_row_threshold` (default: `100_000`) — heat split threshold inside the active window.

`statement_timeout` (default: `300` seconds global default) — per-table override for `run!`.

`retention_months` (default: none) — drop or detach archive partitions older than N months.

`retention_apply` (default: `false`) — when `true`, detach or drop expired archive children; when `false`, notifier logs would-drop partitions only. See [retention.md](retention.md).

`retention_keep_table` (default: `false`) — detach but do not drop expired partitions.

`retention_detach_concurrently` (default: global default) — per-table override for concurrent detach.

`maintenance_backend` (default: `:gardener`) — `:gardener`, `:pg_partman`, or `:hybrid_layout_only`.

`incremental_rebalance` (default: global default) — per-table override.

`run_record_enabled` (default: global default) — per-table override.

`analyze_after_rebalance` (default: global default) — per-table override.

Advanced Ruby-only keys (not in JSON import): `partition_name_format`, `partition_definition`, `extract_partition_identifier` procs. Prefer templates so these defaults stay consistent.

### Maintenance backend

`:gardener` (default) — gardener runs premake, tail rebalance, default drain, and retention; partman runs nothing.

`:pg_partman` — gardener does nothing (table skipped in `run!`); partman runs premake and retention.

`:hybrid_layout_only` — gardener runs tail rebalance, default drain, and gap repair only; partman runs premake and simple retention.

On register, Gardener warns when partman and gardener both claim the same parent. Set `strict_maintenance_backend_validation: true` in `PartitionGardener.configure` to raise `MaintenanceBackend::ValidationError` instead of notifying. See [tooling_split.md](tooling_split.md).

### Suggest a template

```ruby
PartitionGardener.suggest_template(
  table_name: "events",
  partition_key_column: "occurred_on",
  conflict_key: %w[id occurred_on]
)
# => { template:, reliability:, config:, warnings: [] }
```

Use the returned `config` as a starting point for `Registry.register`. `PartitionGardener.recommend` is an alias.

## JSON registry files

Portable table fields are defined in [schemas/partition_garden.schema.json](schemas/partition_garden.schema.json). The schema `$id` is the raw GitHub URL (`https://raw.githubusercontent.com/amkisko/partition_gardener.rb/main/docs/schemas/partition_garden.schema.json`); pin a release tag instead of `main` when you need a fixed version for editor validation. The gem validates against the bundled copy under `docs/schemas/`, not by fetching that URL.

`statement_timeout` is stored in seconds in JSON. Ruby registration accepts integer seconds; when Active Support is loaded, duration helpers such as `10.minutes` are also accepted.

```json
{
  "tables": [
    {
      "table_name": "audits",
      "layout": "sliding_window",
      "partition_key_column": "created_at::date",
      "conflict_key": ["id", "created_at"],
      "active_months": 12,
      "move_batch_size": 10000,
      "statement_timeout": 600,
      "retention_months": 24,
      "maintenance_backend": "gardener"
    }
  ]
}
```

Load from Ruby:

```ruby
PartitionGardener::ConfigDocument.load_registry_file!("config/partition_garden.json")
```

Load from CLI:

```bash
bundle exec partition_gardener --registry config/partition_garden.json audit --all
```

Export from registered Ruby configs:

```ruby
PartitionGardener::ConfigDocument.export(config_hash)
PartitionGardener::ConfigDocument.export_all(PartitionGardener::Registry.tables)
```

JSON import supports layouts: `sliding_window` (with optional `bucket`: day, week, month, quarter), `rolling_current`, `calendar_year`, `premake_monthly`, `integer_window`, `hash_branches`. Composite and `list_split` layouts must be registered in Ruby today.

`load_registry_file!` validates each entry against [schemas/partition_garden.schema.json](schemas/partition_garden.schema.json) (required keys, allowed keys, importable layouts) before registration.

### Registry trust boundary

Registry entries are operator-controlled configuration, not end-user input.

`partition_key_column` and list-branch `where_condition` values are embedded in generated SQL. Keep registry files and Ruby registration limited to trusted operators. Do not load registry JSON from untrusted upload paths without a separate review step.

## Programmatic API

`PartitionGardener.run!(table_name: "audits")` — run maintenance for one table.

`PartitionGardener.run!(job_class_name: "PartitionMaintenanceJob")` — run all registered gardener-owned tables.

`PartitionGardener.run!(dry_run: true)` — build plan reports without applying.

`PartitionGardener.plan(table_name: "audits")` — plan report for one table.

`PartitionGardener.audit("audits")` — read-only layout audit (default rows, gaps, horizon).

`PartitionGardener.suggest_template(...)` — template suggestion (`recommend` is an alias).

`run!` skips tables that are not partitioned, use `maintenance_backend: :pg_partman`, or fail to acquire the advisory lock. Returns `RunSummary`; raises `RunFailed` when `continue_on_error` is false or after aggregating errors at the end.

## Related

- [background_job.md](background_job.md) — schedule `run!` from a host job
- [cli.md](cli.md) — plan, audit, apply from the shell
- [decision_flow.md](decision_flow.md) — when and how to partition
- [operations.md](operations.md) — runbook and RunSummary
- [audit_reference.md](audit_reference.md) — audit and plan fields
- [retention.md](retention.md) — retention options in production

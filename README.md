# Partition Gardener

[![Gem Version](https://badge.fury.io/rb/partition_gardener.svg)](https://badge.fury.io/rb/partition_gardener) [![Test Status](https://github.com/amkisko/partition_gardener.rb/actions/workflows/test.yml/badge.svg)](https://github.com/amkisko/partition_gardener.rb/actions/workflows/test.yml) [![codecov](https://codecov.io/gh/amkisko/partition_gardener.rb/graph/badge.svg)](https://codecov.io/gh/amkisko/partition_gardener.rb)

PostgreSQL partition lifecycle: archive, current, and future zones, heat-driven splits inside the active window, cursor-based rebalance, mandatory default drain, and hot-switch migration helpers. Rails-integrated by default; works standalone with `pg` and a JSON registry.

## Requirements

- Ruby >= 3.2
- PostgreSQL with declarative partitioning
- `pg` gem (runtime dependency)
- Rails >= 7.1 optional — railtie loads when Rails is present and sets Active Record connection plus `Time.zone.today`

Complements migration gems (e.g. [pg_party](https://github.com/rkrage/pg_party)) — use those for creation DDL; use this gem for runtime maintenance (scheduled or indicator-driven) and cutover migrations. See [docs/related_postgres_tooling.md](docs/related_postgres_tooling.md) for how Gardener pairs with [PgHero](https://github.com/ankane/pghero), [Dexter](https://github.com/ankane/dexter), [pgsync](https://github.com/ankane/pgsync), and [pgslice](https://github.com/ankane/pgslice).

## Documentation

### Choosing and configuring

- [docs/decision_flow.md](docs/decision_flow.md) — when to partition, layout, and method choices
- [docs/partition_landscape.md](docs/partition_landscape.md) — templates, Rails sharding, pruning, UI, aggregate snapshots
- [docs/configuration.md](docs/configuration.md) — global config, registry, per-table options, JSON import
- [docs/tooling_split.md](docs/tooling_split.md) — pg_party vs pg_partman vs Gardener
- [docs/related_postgres_tooling.md](docs/related_postgres_tooling.md) — PgHero, Dexter, pgsync, pgslice vs Gardener
- [docs/pg_party_recipe.md](docs/pg_party_recipe.md) — creation DDL with pg_party

### Operations

- [docs/operations.md](docs/operations.md) — runbook, incidents, RunSummary
- [docs/audit_reference.md](docs/audit_reference.md) — audit and plan warning catalog
- [docs/monitoring.md](docs/monitoring.md) — metrics, alerts, SLOs
- [docs/retention.md](docs/retention.md) — detach, drop, compliance, legal hold
- [docs/background_job.md](docs/background_job.md) — host job pattern, concurrency, scheduling
- [docs/cli.md](docs/cli.md) — plan, audit, and apply commands

### Application and migration

- [docs/cutover.md](docs/cutover.md) — hot-switch playbook and template upgrades
- [docs/application_contract.md](docs/application_contract.md) — writes, moves, bulk load, replicas
- [docs/naming.md](docs/naming.md) — child partition naming catalog
- [docs/host_testing.md](docs/host_testing.md) — CI and staging for host apps

### Schemas

- [docs/schemas/](docs/schemas/) — JSON schemas for registry and plan reports

## Quick start

```ruby
# Gemfile
gem "partition_gardener"
```

```ruby
# config/initializers/partition_gardener.rb — see docs/configuration.md for all options
PartitionGardener.configure do |config|
  config.notifier = ->(message, context: {}) { Rails.logger.info(message) }
  config.today_resolver = -> { Time.zone.today }
end

PartitionGardener::Registry.register_template(
  :sliding_window_monthly,
  table_name: "events",
  partition_key_column: "occurred_on",
  conflict_key: %w[id occurred_on],
  active_months: 12
)
```

```ruby
# app/jobs/partition_maintenance_job.rb — see docs/background_job.md
class PartitionMaintenanceJob < ApplicationJob
  def perform
    PartitionGardener.run!(job_class_name: self.class.name)
  end
end
```

```bash
# Dry-run plan from the app directory
bundle exec partition_gardener --rails plan events --pretty
```

### Standalone (no Rails)

Set `DATABASE_URL` and point the CLI at a JSON registry:

```bash
export DATABASE_URL=postgres://postgres@127.0.0.1:5432/mydb
bundle exec partition_gardener --registry config/partition_garden.json plan events --pretty
```

Or configure in Ruby:

```ruby
PartitionGardener.configure do |config|
  config.connection_resolver = -> { PartitionGardener::PgConnection.connect(ENV.fetch("DATABASE_URL")) }
  config.today_resolver = -> { Date.today }
end
PartitionGardener::ConfigDocument.load_registry_file!("config/partition_garden.json")
PartitionGardener.run!
```

## Recommended approach

Default layout: monthly sliding window (`register_template :sliding_window_monthly` in the Rails example above). Three-area layout with planner-enforced non-overlapping ranges, default drained last, and keyset moves on `(partition_key, conflict_key)`.

When you are unsure which template fits, `suggest_template` infers one from partition key column names and returns a draft config plus warnings:

```ruby
result = PartitionGardener.suggest_template(
  table_name: "events",
  partition_key_column: "occurred_on",
  conflict_key: %w[id occurred_on]
)
# => { template: :sliding_window_monthly, config: { ... }, warnings: [], reliability: :recommended }

PartitionGardener::Registry.register(result[:config])
```

`PartitionGardener.recommend` is an alias for `suggest_template`.

Legacy or experimental layouts remain available for composite trees and migrations but log a reliability warning on register.

## Templates

`Templates.sliding_window_monthly` (recommended, layout `:sliding_window`, bucket `:month`) — `RANGE (date)` monthly time-series.

`Templates.sliding_window_daily` (secondary, bucket `:day`) — daily buckets for short retention telemetry.

`Templates.sliding_window_weekly` (secondary, bucket `:week`) — ISO-week buckets.

`Templates.sliding_window_quarterly` (secondary, bucket `:quarter`) — calendar-quarter buckets.

`Templates.calendar_year` (secondary, layout `:calendar_year`) — `RANGE (date)` yearly buckets.

`Templates.rolling_current_monthly` (experimental, layout `:rolling_current`) — monthly sliding window without heat splits.

`Templates.integer_window` (secondary, layout `:integer_window`) — `RANGE (bigint)` id bands.

`Templates.list_split` (secondary, layout `:list_split`) — fixed `LIST` branches.

`Templates.composite_list_hash` (secondary, layout `:composite`) — LIST parent plus HASH sub-trees.

`Templates.composite_list_range` / `Templates.list_range` (experimental) — LIST parent plus RANGE sliding-window sub-trees.

`Templates.composite_range_hash` (experimental) — RANGE parent plus HASH child tables.

`Templates.composite_range_list` (experimental) — RANGE parent plus LIST child tables.

`Templates.hash_branches` (experimental, layout `:hash_branches`) — `HASH` remainders.

`Templates.premake_monthly` (legacy, layout `:premake_monthly`) — cron-style premake bridge; migrate to sliding window.

See [docs/partition_landscape.md](docs/partition_landscape.md) for template matrix, Rails sharding, composite keys, partition pruning, UI and product surfaces, and aggregate snapshots. Operations: [operations.md](docs/operations.md), [cutover.md](docs/cutover.md), [monitoring.md](docs/monitoring.md).

## Hot-switch migrations

`PartitionGardener::Migration::HotSwitchConcern` (alias `HotSwitchPartitionedTable`) consolidates cutover migration helpers.

```ruby
class PartitionEventsHotSwitch < ActiveRecord::Migration[8.0]
  include PartitionGardener::Migration::HotSwitchConcern

  HOT_SWITCH_CONFIG = {
    current_table: "events",
    partitioned_table: "p_events",
    partition_key_column: "occurred_on",
    conflict_key: %w[id occurred_on],
    partition_config: PartitionGardener::Registry.hot_switch_partition_config("events")
  }.freeze

  def up
    ensure_future_partitions_exist(months_ahead: 1)
    hot_switch_tables
  end
end
```

`partition_config` may also be an inline hash for tables not yet registered.

## Runtime guarantees

- Per-table advisory lock during maintenance (`hashtext` namespace plus table name)
- `continue_on_error: true` by default — one failing table does not block others (`PartitionGardener::RunFailed` aggregates errors)
- Batch moves use composite keyset cursors and delete source rows by batch keys
- `run!` returns `RunSummary` with per-table duration, `plan_signature`, and `rows_moved`
- `maintenance_backend: :pg_partman` skips gardener for partman-owned tables

## Tests

App-agnostic PostgreSQL integration specs live under `spec/integration/`. CI and local full-suite runs use [polyrun](https://github.com/amkisko/polyrun) to shard specs across parallel workers (each worker uses its own PostgreSQL database when `DATABASE_URL` is set).

```bash
# Full suite (unit + integration; requires PostgreSQL)
make test

# Same as make test
INTEGRATION=1 DATABASE_URL=postgres://postgres@127.0.0.1:5432/partition_gardener_test ./bin/polyrun parallel-rspec --workers 5

# Unit specs only
bundle exec rspec --exclude-pattern "spec/integration/**/*_spec.rb"

# Integration only (requires PostgreSQL)
INTEGRATION=1 DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/partition_gardener_test bundle exec rake spec:integration
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Sponsors

Sponsored by [Kisko Labs](https://www.kiskolabs.com).

<a href="https://www.kiskolabs.com">
  <img src="kisko.svg" width="200" alt="Sponsored by Kisko Labs" />
</a>

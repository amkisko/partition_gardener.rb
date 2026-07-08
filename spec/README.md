# Testing

## Commands

Full suite (parallel shards; integration specs need PostgreSQL):

```bash
make test
```

`make test` sets `INTEGRATION=1`. Without PostgreSQL, integration examples skip; unit specs still run.

Lint (RuboCop and RBS):

```bash
make lint
```

Focused runs:

```bash
bundle exec rspec spec/partition_gardener/plan_applier_spec.rb
INTEGRATION=1 bundle exec rspec spec/integration/
```

See [POLYRUN.md](../POLYRUN.md) and `polyrun.yml`. Integration spec order is staged in `partition.paths_build.stages`. `make test` runs `hooks.before_suite` before specs.

## Layout

- `spec/partition_gardener/` — unit specs (planner, executor, CLI, strategies)
- `spec/integration/` — PostgreSQL maintenance workflows (skip without `INTEGRATION=1` and a live database)
- `spec/integration/support/` — database helpers and fixtures

## Guidelines

- Test plan, audit, and apply outcomes; mock connections only in unit specs.
- Integration specs require PostgreSQL; CI uses `script/create_postgres_shard_databases.sh`.
- Add or update specs before bugfixes; run `make lint && make test` before a PR.
- Coverage threshold: `config/polyrun_coverage.yml` when `POLYRUN_COVERAGE=1`.

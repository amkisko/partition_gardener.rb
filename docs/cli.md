# CLI

The `partition_gardener` executable plans, audits, and applies maintenance without enqueueing a background job.

```bash
bundle exec partition_gardener --rails plan audits
bundle exec partition_gardener --registry config/partition_garden.json audit --all
bundle exec partition_gardener --rails apply --confirm audits
```

## Commands

`plan` — read-only. Outputs the target layout diff as JSON ([plan_report.schema.json](schemas/plan_report.schema.json)).

`audit` — read-only. Outputs layout audit warnings as JSON (default rows, gaps, horizon).

`apply` — writes data. Runs `PartitionGardener.run!` and prints `RunSummary` JSON. Requires `--confirm`.

## Options

`--rails` — load registry from the host Rails environment (`config/environment.rb`).

`--registry PATH` — load registry from a JSON file ([configuration.md](configuration.md#json-registry-files)).

`--table NAME` — table name (default: first positional argument after the command).

`--all` — all registered tables (plan and audit only; apply runs full registry when omitted with `--all`).

`--pretty` — pretty-print JSON.

`--confirm` — required for `apply` (mutates the database).

Registry context is required. Use `--rails`, `--registry`, or pre-register tables in Ruby before invoking the CLI.

When using `--registry` without `--rails`, set `DATABASE_URL` so the CLI can connect through `PartitionGardener::PgConnection`.

## Examples

Dry-run plan for one table:

```bash
cd /path/to/rails/app
bundle exec partition_gardener --rails plan user_workdays --pretty
```

Audit every table in a JSON registry:

```bash
bundle exec partition_gardener --registry config/partition_garden.json audit --all --pretty
```

Apply maintenance to one table:

```bash
bundle exec partition_gardener --rails apply --confirm audits
```

Apply all registered gardener-owned tables:

```bash
bundle exec partition_gardener --rails apply --all
```

Omitting a table name without `--all` also runs the full registry.

## Related

- [configuration.md](configuration.md) — registry format and global config
- [background_job.md](background_job.md) — when to use a job instead of CLI apply
- [audit_reference.md](audit_reference.md) — audit and plan output reference
- [operations.md](operations.md) — when to plan vs apply

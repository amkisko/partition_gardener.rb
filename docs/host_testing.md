# Host application testing

How consuming Rails apps (and standalone services) test partitioned tables alongside Partition Gardener. Gem-internal testing lives in [spec/README.md](../spec/README.md).

## Goals

- Prove registry config matches production templates.
- Prove `plan` / `audit` stay clean on CI data.
- Catch application queries that omit the partition key before production.

## CI database

Use a real PostgreSQL instance in CI (same major version as production). Docker service or CI-provided Postgres is enough.

Minimal env:

```bash
export DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/myapp_test
export INTEGRATION=1  # if reusing gardener integration patterns
```

Load schema including partitioned parents created by migrations (pg_party or SQL).

## Registry in test

Use the same registry as production in `config/initializers/partition_gardener.rb` or load `config/partition_garden.json` in test with the same template names. Staging should use the same `active_months`, `retention_months`, and `conflict_key` as production unless you intentionally test divergence.

Smoke after migrations:

```ruby
RSpec.describe "partition registry" do
  it "audits clean for registered tables" do
    PartitionGardener::Registry.configs.each do |config|
      result = PartitionGardener.audit(config[:table_name])
      expect(result.partitioned).to be(true)
      expect(result.warnings).to be_empty
    end
  end
end
```

Run only when PostgreSQL is available; skip in unit-only jobs.

## Application contract specs

Test behavior, not implementation:

- Scoped queries used by controllers return rows only inside the requested window.
- `create!` with partition key lands queryable row without relying on `default`.
- Snapshot totals match fixture sums for a single bucket after recompute job.

Avoid asserting exact partition child table names unless testing migration code.

## Gardener maintenance in test

Optional nightly-style test on a disposable table:

```ruby
PartitionGardener.run!(table_name: "events", dry_run: true)
PartitionGardener.run!(table_name: "events")
```

Use a dedicated test parent or truncate children in `around` hooks; do not run full `apply --all` against shared dev databases without isolation.

## Staging checklist

- [ ] Same PostgreSQL major version
- [ ] Same registry templates and `active_*` spans
- [ ] `today_resolver` uses app time zone
- [ ] Maintenance job schedule enabled
- [ ] Audit cron or monitoring wired ([monitoring.md](monitoring.md))
- [ ] Cutover playbook exercised once on clone ([cutover.md](cutover.md))

## Staging data with pgsync

[pgsync](https://github.com/ankane/pgsync) copies rows between Postgres databases. Use it to refresh staging with a production-shaped subset before exercising `plan`, `run!`, or cutover drills.

Practices:

- Default destination is localhost unless `to_safe: true` — confirm the target URL before each run.
- Filter with `where` on the partition key so staging holds realistic month windows without full production volume.
- Use `--in-batches` on large append-only tables; schedule loads outside Gardener `run!` so rebalance and sync do not contend on the same parent.
- Apply `data_rules` when copying from production so secrets and PII are redacted in staging.

Gardener does not invoke pgsync. After sync, run `audit` and `plan` on registered tables before enabling nightly maintenance in staging.

## Related

- [application_contract.md](application_contract.md) — what to test
- [cli.md](cli.md) — local plan and audit
- [configuration.md](configuration.md) — JSON registry for non-Rails

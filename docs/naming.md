# Partition naming catalog

How Gardener names children so operators can read `pg_catalog`, audit output, and `plan` JSON without guessing.

## Tail slots (three-area layout)

Fixed suffixes on the parent table name:

`{table}_default` — catch-all; must trend empty.

`{table}_current` — start of active window.

`{table}_open` — gap filler in current zone.

`{table}_open_N` — extra fillers after heat splits.

`{table}_future` — open-ended tail to MAXVALUE.

`{table}_rebalance_staging` — temporary during tail rebalance.

Defined in `PartitionGardener::Naming`.

## Archive buckets (date range)

Pattern: `{table}_{suffix}` where suffix comes from `DateBucket.partition_name_suffix`:

month — suffix example `events_2026_03`, bounds `[2026-03-01, 2026-04-01)`.

day — suffix example `events_2026_03_15`, bounds one day.

week — suffix example `events_2026_W10`, bounds ISO week.

quarter — suffix example `events_2026_Q1`, bounds calendar quarter.

year — suffix example `events_2026`, bounds calendar year.

Gardener parses archive names back to bucket starts for retention and heat maps. Manual names outside these patterns are ignored for archive retention and may become orphans.

## Integer and hash layouts

- Integer window: band names follow strategy config (`active_id_lo`, band width).
- Hash branches: remainder or modulus in name per `hash_branches` template.
- List split: branch label from registry `branches` hash.

See template builders in [configuration.md](configuration.md).

## Composite trees

- LIST parent: branch discriminator in child name.
- Sub-trees: `{parent}_{branch}` registered as separate gardener tables.
- Native PostgreSQL sub-partition names must stay consistent with what `expand` registers; gardener plans per registered node ([partition_landscape.md](partition_landscape.md#composite-trees)).

## Hot-switch rename

After `hot_switch_tables`, children rename from `p_events_*` to `events_*` to match the production parent prefix. Plan audits using the post-switch names.

## Drift from manual DDL

Symptoms:

- `partition gap` warnings in audit
- `plan` shows `reshape` or `drop` on unexpected names
- Retention skips or targets wrong children

Remediation: prefer `plan` + `apply` over manual attach. If manual children are required, match `FOR VALUES` bounds to planner segments exactly.

## Related

- [operations.md](operations.md) — gap remediation
- [cutover.md](cutover.md) — shadow `p_` prefix
- [audit_reference.md](audit_reference.md) — gap messages

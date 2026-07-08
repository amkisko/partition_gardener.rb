# Retention and compliance

How archive partitions leave the database when `retention_months` is set, and how to coordinate drops with policy, backups, and legal hold.

Configuration reference: [configuration.md](configuration.md) (`retention_months`, `retention_apply`, `retention_keep_table`, `retention_detach_concurrently`).

## How gardener applies retention

After layout work on a date-range sliding window, `ArchiveRetention`:

1. Computes cutoff: `today - retention_months` (calendar months via `DateCalendar`).
2. Walks attached non-default children.
3. Skips default, current/open/future tail slots, and managed tail names.
4. For archive buckets strictly before cutoff month: detach, then drop unless `retention_keep_table`.

Detach uses `ALTER TABLE … DETACH PARTITION`; drop uses `DROP TABLE` on the child. With `retention_detach_concurrently: true`, detach runs `CONCURRENTLY` (PostgreSQL 14+).

Preview by default: when `retention_months` is set and `retention_apply` is omitted or `false`, retention only logs would-drop partitions via `notifier`. Set `retention_apply: true` on the registry entry before archive children detach or drop.

## Detach vs drop

Drop (default) — `retention_keep_table: false`. Child removed from parent and dropped.

Archive tables — `retention_keep_table: true`. Child detached but table remains in schema for cold storage or export.

Use `retention_keep_table: true` when compliance requires a quarantine period before physical drop, or when moving data to object storage from detached tables.

## Before first production drop

1. Confirm backup scope includes detached children or that exports completed.
2. Run `plan` and review retention segment in operations log.
3. Verify no legal hold on periods older than cutoff.
4. Invalidate or freeze snapshot rows for dropped buckets ([partition_landscape.md](partition_landscape.md#aggregates-totals-and-snapshots)).
5. Document dropped partition names ([naming.md](naming.md)) in change records.

## Legal hold and GDPR

Partition Gardener has no legal-hold flag. Host applications implement hold by:

- Omitting `retention_months` until hold clears, or
- Setting `retention_keep_table: true` and managing detached tables manually, or
- Excluding specific buckets via registry change and manual attach (last resort).

Right-to-erasure across partitions still requires row-level delete or targeted child operations; dropping an entire month may suffice when all rows in that period are in scope for deletion and policy allows bulk removal.

Coordinate with counsel before using partition drop as an erasure mechanism.

## pg_partman retention

When `maintenance_backend: :pg_partman`, gardener skips the table; partman owns retention. Hybrid mode: partman premake plus gardener layout only ([tooling_split.md](tooling_split.md)). Do not configure conflicting retention on both sides.

## Operational checklist

- [ ] `retention_months` matches product policy document
- [ ] Backup verified for oldest archive month before first automated drop
- [ ] `retention_apply: true` only after backup and policy sign-off
- [ ] Monitoring alert on retention notifier messages
- [ ] Rollup snapshots updated or marked inactive for dropped buckets
- [ ] Runbook entry for restoring from backup if drop was premature ([operations.md](operations.md))

## Related

- [decision_flow.md](decision_flow.md) — retention in layout choice
- [operations.md](operations.md) — incident response
- [monitoring.md](monitoring.md) — alerts

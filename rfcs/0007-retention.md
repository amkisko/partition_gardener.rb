# RFC 0007: Archive retention

- Feature Name: retention
- Type: Standards Track
- Status: Stable
- Created: 2026-09-09
- Author: Andrei Makarov
- Stakeholders: project maintainers
- Relates: RFC 0006, RFC 0009
- Requires: RFC 0003

## Summary

Specify when date-range archive children detach or drop. Preview is the default. Tail slots and default are never retention targets.

## Motivation

A mistaken drop removes months of facts. Operators need a numbered cutoff, skip list, and an explicit apply flag before gardener mutates archive children.

## Guide-level explanation

With `retention_months: 24` and `retention_apply` omitted, a run notifies `Would drop archive partition events_2024_08 ...` and leaves the child attached. After backup sign-off, set `retention_apply: true`. Children whose parsed bucket start is strictly before the cutoff month detach, then drop unless `retention_keep_table` is true.

## Reference-level explanation

Applies only to `Strategy::DateRange`. Other layouts return zero drops.

Cutoff is `today` minus `retention_months` calendar months. A child is eligible when `archive_bucket_from_partition_name` returns a date strictly before the beginning of that cutoff month.

Skip: DEFAULT, tail-slot names (`_current`, `_open`, `_open_N`, `_future`), and managed tail names. Unparseable names skip (RFC 0006).

When `retention_apply` is false or omitted, notify would-drop and do not detach. When true: `ALTER TABLE … DETACH PARTITION`, then `DROP TABLE` unless `retention_keep_table`. `retention_detach_concurrently: true` uses `DETACH PARTITION CONCURRENTLY` (PostgreSQL 14+).

Hybrid backend (RFC 0009) does not run this retention in gardener.

Gardener has no legal-hold flag. Hold is a host policy: omit `retention_months`, keep detached tables, or stop automated apply.

### Fail modes

Missing `retention_months` is a no-op. Preview MUST NOT detach. A detach or drop error is a run error (RFC 0005), not a silent skip of later children unless `continue_on_error` applies at the table runner.

## Implementation notes

`lib/partition_gardener/archive_retention.rb`. Called from `DateRangeMaintenance` after archive finalize, before default drain.

## Registrar

`retention_months`, `retention_apply`, `retention_keep_table`, `retention_detach_concurrently`.

## Drawbacks

Preview-by-default can look like retention is on when children never leave. Concurrent detach is version-gated.

## Rationale and alternatives

Preview first avoids a first-production drop from a copied registry. Rejected: dropping tail slots. Rejected: a built-in legal-hold column.

## Prior art

pg_partman retention functions. Host compliance runbooks.

## Unresolved questions

Whether integer-window bands should gain the same preview/apply split.

## Future possibilities

Per-bucket hold lists. Coordinating drop with snapshot freeze in the host app.

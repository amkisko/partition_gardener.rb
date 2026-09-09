# RFC 0006: Archive date-bucket names

- Feature Name: archive-naming
- Type: Standards Track
- Status: Stable
- Created: 2026-09-09
- Author: Andrei Makarov
- Stakeholders: project maintainers
- Relates: RFC 0002, RFC 0003, RFC 0007

## Summary

Specify how date-range archive children are named and parsed. Tail slots stay in RFC 0002. Names outside these patterns are not retention targets.

## Motivation

Retention and heat maps parse child names back to bucket starts. A silent rename would drop the wrong month or skip a child the operator expected to expire.

## Guide-level explanation

A monthly child for March 2026 is `events_2026_03` with bounds `[2026-03-01, 2026-04-01)`. A day child is `events_2026_03_15`. An ISO week is `events_2026_W10`. A quarter is `events_2026_Q1`. A year is `events_2026`. `plan` keeps those names when occupancy already holds the bounds.

## Reference-level explanation

Pattern: `{table}_{suffix}`. Suffix from `DateBucket.partition_name_suffix`:

- month: `%Y_%m` (optional `_01` is also parsed)
- day: `%Y_%m_%d`
- week: `%G_W%V`
- quarter: `{year}_Q{1-4}`
- year: `{year}`

`archive_bucket_from_partition_name` returns the bucket start date, or nil when the name does not match. Nil means skip for archive retention (RFC 0007) and ignore for archive heat. Manual names outside the pattern MAY remain attached; they are not archive buckets.

`{table}_rebalance_staging` is the temporary rebalance child (RFC 0010), not an archive bucket.

Hot-switch (RFC 0012) renames `p_{table}_*` to `{table}_*` so names match this catalog after swap.

### Fail modes

Parse MUST NOT treat `_current`, `_open`, `_open_N`, `_future`, or `_default` as archive suffixes. Overlapping `FOR VALUES` on two date names remains a Postgres attach error.

## Implementation notes

`lib/partition_gardener/date_bucket.rb`. Integer and hash names are RFC 0014 and RFC 0015.

## Registrar

Date-bucket suffixes above. `DateBucket.partition_name`.

## Drawbacks

Operators who attach `events_march_2026` never get retention from gardener.

## Rationale and alternatives

Parse-back from the name keeps retention off catalog comments. Rejected: storing bucket metadata in a side table.

## Prior art

pg_partman numbered children. pgslice date-stamped children.

## Unresolved questions

Whether uncovered months after occupancy should be premade as these named buckets instead of `_open` (RFC 0002).

## Future possibilities

Custom `partition_name_format` remaining Ruby-only (RFC 0004).

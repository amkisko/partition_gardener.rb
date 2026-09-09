# RFC 0014: Integer window layout

- Feature Name: integer-window
- Type: Standards Track
- Status: Stable
- Created: 2026-09-09
- Author: Andrei Makarov
- Stakeholders: project maintainers
- Relates: RFC 0002, RFC 0003

## Summary

Specify `integer_window`: id bands for archive and a current hot range, a required default, and explicit unresolved occupancy (RFC 0002 does not walk integer catalogs yet).

## Motivation

Serial or bigint keys need RANGE children by id, not by date. Operators copying date occupancy into id space would mis-name `_current` and `_future`. This RFC records the shipped band math and the occupancy gap.

## Guide-level explanation

`register_template :integer_window` with defaults plans archive bands of width 10000000 from `active_id_lo` 0, current hot children `{table}_ids_{lo}_{hi}` inside a 10000000-wide active span split by `current_band_size` 1000000, plus `{table}_default`. Until occupancy ships, `plan` does not treat an attached id child as filling a tail slot the way RFC 0002 does for dates.

## Reference-level explanation

Defaults: `active_id_lo` 0, `active_id_width` 10000000, `current_band_size` 1000000, `archive_band_size` 10000000. Hot names `{table}_ids_{lo}_{hi}`. Default partition is required.

JSON import MAY load `integer_window` (RFC 0004).

Do not claim an occupancy walk for integer children. Tail slot names from RFC 0002 MAY appear if a host attached them by hand; gardener MUST NOT treat that as specified integer occupancy.

### Fail modes

Overlapping id `FOR VALUES` is a Postgres error. A MAXVALUE integer tail is not specified here.

## Implementation notes

`lib/partition_gardener/strategy/` integer window. Occupancy files apply to date-range only today.

## Registrar

Layout `integer_window`. Template `integer_window`. Keys `active_id_lo`, `active_id_width`, `current_band_size`, `archive_band_size`.

## Drawbacks

Without occupancy, an existing wide id child can overlap planned bands and fail attach. Operators must read this RFC's unresolved question before copying date runbooks.

## Rationale and alternatives

Separate layout keeps date window math (RFC 0003) from growing id branches. Rejected: pretending RFC 0002 already covers integer catalogs.

## Prior art

pg_partman integer partitioning. RANGE on bigint.

## Unresolved questions

Whether integer occupancy should reuse RFC 0002 occupant rules (attached, not DEFAULT, not tail-slot name) with `range_end` compared to `active_id_lo + active_id_width`. Whether `_future` for integer is MAXVALUE or the next unused band.

## Future possibilities

Occupancy for integer as a follow-on RFC that Relates to RFC 0002. Retention of archive id bands.

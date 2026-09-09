# RFC 0002: Tail slot names and occupancy

- Feature Name: tail-slots
- Type: Standards Track
- Status: Proposed
- Created: 2026-09-09
- Author: Andrei Makarov
- Stakeholders: project maintainers
- Feedback until: 2026-09-23
- Relates: RFC 0001

## Summary

Name `_current`, `_open`, and `_future` by placement on an uncovered range. A date-named child that already covers a range is that range. Do not plan a tail slot over it. `_default` is the unmatched-insert residual, not a range occupant. This RFC does not add registry flags.

## Motivation

Operators read `{table}_current` as this month. The three-area layout uses `_current` for the filler that starts at the active-window origin and may span many buckets. Always-create planned `_current` over a month the catalog already held as `events_2026_09_01`. The same overlap exists at the high end: `_future` from the window end overlays a premade month that starts there. Postgres RANGE children cannot overlap. Insertion order does not matter. Bounds do.

## Guide-level explanation

On 2026-09-09, `events_2026_09_01` is attached for September. `partition_gardener plan events` keeps that child. It does not list `events_current`. If later buckets in the active window are uncovered, it lists `events_open` from the first uncovered instant. If `events_2026_10_01` is also attached and the window ends 2026-10-01, it does not list `events_future` from 2026-10-01. `_future` starts at 2026-11-01, after that month, unless some attached child already ends at MAXVALUE.

An empty origin still gets `_current` from the window start, then `_future` from the window end when nothing occupies those ranges. That is today's catalog when no named months sit in the way.

## Reference-level explanation

### Names

`{table}_current` is the current-zone filler whose `range_start` equals the active-window origin. It is not this calendar month and not this integer sequence value.

`{table}_open` is the current-zone filler whose `range_start` is after the origin, including after an occupying named child or a heat split. Further fillers are `{table}_open_N`. `_open` is not used past `active_end`.

`{table}_future` is the child whose `range_end` is MAXVALUE. `range_start` is the first instant at or after `active_end` that no occupying child covers.

`{table}_default` is the PostgreSQL DEFAULT partition. Occupancy does not skip or create it.

### Occupant

An occupant is an attached child that is not DEFAULT and not a tail-slot name (`_current`, `_open`, `_open_N`, `_future`). Occupancy is `FOR VALUES` bounds, not a parsed monthly name.

Occupants that overlap `[active_start, active_end)` stay in the plan with catalog names and bounds. Archive children that end at or before `active_start` stay archive.

Occupants that cover any key at or after `active_end` stay in the plan with catalog names and bounds. That includes a premade month whose `range_start` equals `active_end`, and a child that straddles `active_end`.

### Creation

Plan `_current` only when a filler run starts at `active_start` and no occupant covers that origin.

Plan `_open` only for uncovered current-zone runs after the origin.

Plan `_future` only when no occupant has `range_end` MAXVALUE. `range_start` is the later of `active_end` and the maximum finite `range_end` among occupants that cover any key at or after `active_end`. Holes between those occupants are gaps. `_future` MUST NOT fill a hole that would overlap a later occupant.

Heat-split months already in the plan occupy those buckets the same way.

### Fail modes

`plan` MUST NOT emit overlapping `FOR VALUES` ranges. `apply` MUST NOT attach a child that overlaps an attached occupant. Postgres routing errors on insert remain the host contract for keys that match no child.

## Implementation notes

Window occupancy lives in `lib/partition_gardener/layout/occupied_window.rb` and `lib/partition_gardener/layout/zone_segments.rb`. Occupants that overlap the active window or cover any key at or after `active_end` stay in the plan. `_future` starts after those high-end occupants, and is omitted when an occupant already ends at MAXVALUE.

## Drawbacks

A distant premade month past the window pushes `_future` after that month and leaves a gap in between. Catalogs that wanted `_current` over months they already named must keep the named children or detach them first.

## Rationale and alternatives

Folding occupied months into `_current` needs ACCESS EXCLUSIVE and row moves. Forcing `_current` after occupancy misnames the filler. Always-create `_future` from `active_end` repeats the September overlap on the next month. Registry flags can opt out of empty-range slots later. They are not required to stop overlap.

Rejected: treating `_default` as a third name for the same month. DEFAULT is residual routing.

## Prior art

PostgreSQL RANGE partitions must not overlap. pg_partman premake creates numbered children without a current slot name. pgslice uses intermediate plus default.

## Unresolved questions

Whether uncovered months after occupancy should be premade as named buckets instead of one `_open`.

Whether integer-window active-band fillers use the same occupancy walk.

Whether holes between high-end occupants should stay gaps or gain extra fillers without overlapping named months.

Whether `_future` `range_start` after `active_end` should change the MAXVALUE audit text.

## Future possibilities

Registry booleans to skip `_current`, `_future`, or `_default` when the range is empty. Layout-specific template defaults for `premake_monthly`. A drain target other than default.

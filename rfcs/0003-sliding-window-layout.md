# RFC 0003: Sliding window three-area layout

- Feature Name: sliding-window-layout
- Type: Standards Track
- Status: Stable
- Created: 2026-09-09
- Author: Andrei Makarov
- Stakeholders: project maintainers
- Relates: RFC 0001, RFC 0002

## Summary

Specify the default date-range layout: archive before the active window, a bounded current zone with optional heat splits, one MAXVALUE tail, and a mandatory default drained last. Tail slot names and occupancy stay in RFC 0002.

## Motivation

Operators pick `sliding_window` and `active_months` without a numbered contract for window math, heat, or drain order. Changing those bytes would break catalogs that already follow the planner.

## Guide-level explanation

On 2026-09-09, `register_template :sliding_window_monthly` with `active_months: 12` plans archive months before 2026-09-01, a current zone `[2026-09-01, 2027-09-01)`, and `_future` from 2027-09-01 unless occupancy (RFC 0002) already covers that range. A month inside the window with at least 100000 rows gets its own named child. `apply` drains `{table}_default` after layout and retention.

## Reference-level explanation

### Window

`active_start` is the beginning of the bucket that contains `today`. `active_end` is `active_start` plus the active span for that bucket. Defaults: 12 months, 90 days, 52 weeks, 8 quarters, 2 years. Registry keys `active_months`, `active_days`, `active_weeks`, `active_quarters`, `active_years` override the span. Archive children end at or before `active_start`.

### Zones

Archive: named date buckets before `active_start`. Current: `[active_start, active_end)` filled by occupants, heat children, `_current`, and `_open` as RFC 0002. Future: one child whose `range_end` is MAXVALUE, or omitted when occupancy already ends at MAXVALUE. Default: `{table}_default` is always planned for this layout.

### Heat

Inside the current zone, a bucket whose row count is at least `split_row_threshold` (default 100000) is a dedicated child named by the date-bucket suffix. Fillers cover the remainder. `rolling_current` uses the same zones with no heat splits. `calendar_year` uses year buckets and `active_years`. `premake_monthly` is not this layout.

### Drain

Maintenance creates or keeps default first, rebalances the tail, then (unless hybrid, RFC 0009) finalizes archive and retention, then drains default last. Default MUST trend toward zero rows. Inserts without a matching child still raise a PostgreSQL routing error; that is the host contract.

### Fail modes

`plan` MUST NOT emit overlapping `FOR VALUES` ranges. Holes between occupants stay gaps. Integer occupancy is RFC 0014, not this walk.

## Implementation notes

Window and segments: `lib/partition_gardener/layout/sliding_window.rb`, `lib/partition_gardener/layout/zone_segments.rb`. Drain order: `DateRangeMaintenance#run!`.

## Registrar

`layout` value `sliding_window`. Template names `sliding_window_monthly`, `sliding_window_daily`, `sliding_window_weekly`, `sliding_window_quarterly`.

## Drawbacks

A wide window plus heat splits grows the catalog. Operators who wanted premade months only must use `premake_monthly` or occupancy (RFC 0002).

## Rationale and alternatives

Three areas keep a bounded current span and one future tail instead of creating every month ahead. Rejected: premake-only as the default. Rejected: draining default before attach, which races inserts into a hole.

## Prior art

PostgreSQL RANGE children must not overlap. pg_partman premake creates numbered children without a current filler.

## Unresolved questions

Whether heat children that later fall below the threshold must merge back in the same run.

## Future possibilities

Registry flags to skip empty tail slots (RFC 0002). A drain target other than default.

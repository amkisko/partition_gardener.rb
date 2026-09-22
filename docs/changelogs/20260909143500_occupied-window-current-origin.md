# Occupied window current origin

## Participants

Andrei

## Decisions

Date-range planning keeps attached monthly children whose ranges overlap the active window. The remainder after a contiguous occupying prefix from the window start is named open. Current is reserved for a filler that starts at the window origin. OccupiedWindow reads Connection.attached_partitions bounds. ZoneSegments walks those catalog segments before heat splits and fillers. Monthly name parse also accepts an optional first-of-month suffix so those child names resolve as that month.

A later pass changed the remainder name from current to open so the slot matches the documented origin rule.

## Effects

A monthly catalog through the current month no longer plans a current partition that overlaps the occupying child. Postgres attach of the remainder filler starts at the next month as open.

## Source

Follows usr/docs/issues/20260909143500_occupied-window-current-origin.md. Specs: spec/partition_gardener/date_range_occupied_window_spec.rb, spec/partition_gardener/sliding_window_spec.rb, spec/integration/sliding_window_maintenance_spec.rb.

# High-end occupancy for future

## Participants

Andrei

## Decisions

A date-named child that covers keys at or after the active window end stays in the plan. Future starts after the latest finite end among those occupants. Future is omitted when an occupant already ends at MAXVALUE. Holes between those occupants stay gaps. Default remains residual routing. No registry flags.

## Effects

The sliding-window planner keeps a premade month that begins at the window end and starts future from the next month. A child that straddles the window end pushes future to that child's end. Noncontiguous premade months past the window stay attached. Apply no longer attaches future over a month that already occupies that range.

## Next

Discuss RFC 0002 unresolved questions. Integer-window occupancy is unchanged.

## Source

Follows rfcs/0002-tail-slots.md and usr/docs/issues/20260909143500_occupied-window-current-origin.md.

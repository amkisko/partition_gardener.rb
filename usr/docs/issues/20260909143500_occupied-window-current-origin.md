# Occupied monthly children at the active window start

## Participants

Andrei

## Decisions

When attached monthly children already cover the start of the sliding-window active range, the plan keeps those children and fills the remainder as open, not current. Current is only the filler that starts at the active window origin. The planner reads occupancy from attached range bounds, not only from parsed monthly names.

Archive children whose range ends at or before the window start stay archive. Tail slot names current, open, and future are not occupancy. A first-month heat split that is not yet attached already named the later filler open; occupied prefix uses the same name.

RFC 0002 records occupancy-first placement. A date-named child that covers a range is that range. Current, open, and future fill only uncovered ranges. Default is residual routing. This patch does not add registry flags. A later RFC 0002 pass dropped ensure flags from the draft and added high-end occupancy for future versus premade months past the window.

## Effects

A catalog of monthly children through the current month, with default only and no current or future slot, plans open from the next month and attaches without overlapping an existing child. A premade month that begins at the window end stays attached. Future starts after that month.

## Next

RFC 0002 stays Proposed. Unresolved questions live in the RFC, including integer occupancy. Implementation PRs cite RFC-0002.

## Source

Requested as a sliding-window plan fix after 0.3.3 skipped only the reverse overlap, archive attach when current already covers that month. Naming follow-up: current must not start after the occupying prefix.

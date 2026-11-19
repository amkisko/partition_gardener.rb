# Premake monthly default overlap create

## Participants

Andrei Makarov

## Decisions

- Fix PremakeMonthlyMaintenance so missing month children are materialized through ensure_archive_partition_attached! with the default partition as the source when it exists.
- Add materialize_partition_from_source! that locks the parent for writes, drains overlapping rows into a detached child, then attaches.
- Keep create/attach CheckViolation recovery via a savepoint so an outer advisory transaction stays usable.

## Effects

- Integration fixtures with synthetic rows in the default for the current and next month complete without CheckViolation; row identity stays on the parent; children hold the moved rows.
- Second maintenance pass is a no-op for already-attached months.

## Next

- Distill into CHANGELOG.md Unreleased; cut a patch release when ready.

## Source

- docs/issues/20261119083632_premake-monthly-default-overlap-create.md

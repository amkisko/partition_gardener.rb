# Premake monthly create fails when the default partition already holds that month

## Participants

Andrei Makarov

## Decisions

- On the first-create path, move overlapping default rows into a detached child and attach under a parent `SHARE ROW EXCLUSIVE` write lock in one transaction (or under the existing advisory transaction when one is open).
- Reuse the archive materialize helper from date-range maintenance so premake and archive attach share the same drain-then-attach contract.
- Wrap speculative `CREATE TABLE ... PARTITION OF` and bare `ATTACH` attempts in a savepoint when an outer transaction is open so a `CheckViolation` does not abort the whole table run.

## Effects

- Before: PremakeMonthlyMaintenance called `create_partition` for missing months before `drain_default_partition`. A row already in the default for that month raised `ActiveRecord::CheckViolation` (`updated partition constraint for default partition ... would be violated by some row`).
- After: the same fixture ends with the matching rows in the monthly children, November-style horizon children attached, default empty for those keys, and a second ordinary maintenance pass clean.
- Regression coverage: `spec/integration/premake_monthly_spec.rb` (overlap create and second pass); `spec/partition_gardener/attach_retry_spec.rb` updated for the lock path.

## Next

- Publish `0.3.10` (`make release` after commit and clean tree). Host apps that added a one-off preparation step before `run!` can drop it once that version is locked.

## Source

- lib/partition_gardener/premake_monthly_maintenance.rb
- lib/partition_gardener/date_range_maintenance.rb
- spec/integration/premake_monthly_spec.rb
- docs/changelogs/20261119083632_premake-monthly-default-overlap-create.md

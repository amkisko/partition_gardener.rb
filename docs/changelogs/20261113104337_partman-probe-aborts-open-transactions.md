# Register-time partman probe no longer aborts an open transaction when partman.part_config is missing.

## Participants

Andrei Makarov (@amkisko)

## Decisions

- Gate the `partman.part_config` SELECT on `to_regclass(...)::text` so absence is a null result, not an error that marks the transaction aborted.
- Document that a savepoint wrap also works but costs more on the common no-partman path.

## Effects

- `Registry.register` / `MaintenanceBackend.validate!` stay safe inside RSpec transactional examples and other outer transactions without pg_partman.
- Host prepend workarounds that only checked `to_regclass` can be removed after this gem version is locked.

## Next

- Cut into CHANGELOG under `## 0.3.9 (2026-11-13)`.
- Commit, tag `0.3.9`, push, and run `make release`.

## Source

- docs/issues/20261113104337_partman-probe-aborts-open-transactions.md
- lib/partition_gardener/connection.rb
- spec/integration/partman_probe_transaction_spec.rb

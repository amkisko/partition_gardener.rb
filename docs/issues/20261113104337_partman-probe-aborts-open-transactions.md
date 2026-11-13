# When partman.part_config is absent, the register-time probe still aborts an open Postgres transaction after Ruby rescues StatementInvalid.

## Participants

Andrei Makarov (@amkisko)

## Decisions

- Probe with `to_regclass('partman.part_config')::text` before selecting from the table so a missing relation returns null instead of raising.
- Keep `MaintenanceBackend.partman_parent_configured?` rescue as defense for unrelated statement failures.
- Prefer `to_regclass` over a savepoint wrap: local measurement showed the missing-relation savepoint path about 3x slower than the catalog null check.

## Effects

- Reproduced before the fix: `MaintenanceBackend.partman_parent_configured?` returned false inside an open transaction, then `SELECT 1` raised `PG::InFailedSqlTransaction`.
- After the fix: the same sequence leaves the outer transaction usable; `Registry.register` no longer poisons transactional RSpec examples on DBs without pg_partman.
- Integration specs cover absent probe, register inside a transaction, and a hit when a stub `partman.part_config` lists the parent.

## Next

- Publish `0.3.9` (`make release` after commit and clean tree). Host apps can drop prepend workarounds once that version is locked.
- Optional later: cache the relation presence check across a register burst if register volume ever makes the extra round trip when partman is installed measurable.

## Source

- lib/partition_gardener/connection.rb (`partman_parent_configured?`)
- lib/partition_gardener/maintenance_backend.rb
- spec/integration/partman_probe_transaction_spec.rb
- docs/changelogs/20261113104337_partman-probe-aborts-open-transactions.md

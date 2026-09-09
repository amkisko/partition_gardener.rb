# RFC 0009: Maintenance backends

- Feature Name: maintenance-backends
- Type: Standards Track
- Status: Stable
- Created: 2026-09-09
- Author: Andrei Makarov
- Stakeholders: project maintainers
- Relates: RFC 0003, RFC 0005, RFC 0007

## Summary

Specify who owns premake, tail rebalance, default drain, archive finalize, and retention: gardener, pg_partman, or hybrid.

## Motivation

Two tools claiming the same parent duplicate children or drop the other's work. Operators need a registry key and a dual-claim check before `run!`.

## Guide-level explanation

Default `maintenance_backend: gardener` runs the full date-range loop. `pg_partman` skips gardener work and records `skip_reason` `maintenance_backend_pg_partman`. `hybrid_layout_only` lets gardener rebalance the tail, drain default, and repair gaps; archive finalize and retention stay with partman.

## Reference-level explanation

Allowed values: `gardener` (default), `pg_partman`, `hybrid_layout_only`. Unknown values fail registry load (RFC 0004).

`gardener`: premake, occupancy layout (RFC 0002), tail rebalance, default drain, archive finalize, retention (RFC 0007).

`pg_partman`: `run!` skips the table. Audit still reads the catalog.

`hybrid_layout_only`: gardener performs tail rebalance, default drain, and gap repair. Gardener MUST NOT finalize archive children or apply retention.

### Dual-claim

When `pg_partman.part_config` exists for the parent and the registry backend is `gardener`, warn. When the backend is `pg_partman` or `hybrid_layout_only` and no partman row exists, warn. `strict_maintenance_backend_validation: true` raises `MaintenanceBackend::ValidationError` instead of warning.

### Fail modes

Skip MUST NOT raise out of `run!`. ValidationError stops that table. Hybrid without a partman row is a warning or raise, not a silent full gardener run.

## Implementation notes

`lib/partition_gardener/maintenance_backend.rb`. Date-range skip of archive/retention on hybrid is in `DateRangeMaintenance`.

## Registrar

`maintenance_backend`, `strict_maintenance_backend_validation`. Skip reason `maintenance_backend_pg_partman`. `MaintenanceBackend::ValidationError`.

## Drawbacks

Hybrid still requires partman to exist for the check. Operators can set gardener while partman cron also runs if they ignore warnings.

## Rationale and alternatives

A registry enum is cheaper than inspecting every cron. Rejected: auto-switching backend from `part_config` presence.

## Prior art

pg_partman `part_config`. One-owner guidance in `docs/partition_engines.md` (operator material, not this RFC).

## Unresolved questions

Whether hybrid should ever run gardener retention on a named allowlist of tables.

## Future possibilities

A backend for other extension catalogs. A read-only dual-claim audit without `run!`.

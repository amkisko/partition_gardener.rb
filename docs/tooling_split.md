# Tooling split: DDL creation, runtime maintenance, and extension maintenance

Partition work splits into three layers. Each layer has a different owner and schedule. Mixing owners on the same parent table without an explicit contract causes overlapping bounds, double drops, and rows stuck in the default partition.

## pg_party — creation (DDL)

Use during migrations and cutover.

- Create partitioned parent and first children
- Attach indexes across children
- Model helpers for partition DDL

pg_party does not replace nightly maintenance. After cutover, hand the table to runtime maintenance.

## pg_partman — extension runtime maintenance (premake and retention)

Use when the hosting environment allows the extension and the table is a plain time or id series.

- Premake upcoming intervals on a fixed cadence
- Retention via detach or drop
- Background worker or `run_maintenance_proc`

partman fits tables that do not need three-area layout, heat splits inside current, or default-last drain logic.

Register such tables with `maintenance_backend: :pg_partman` so Partition Gardener skips them.

## Partition Gardener — application runtime maintenance (layout)

Use for runtime maintenance when layout is more than fixed premake.

- Sliding window archive, current, and future
- Heat-driven splits inside current
- Mandatory default drain last
- Incremental tail rebalance and gap detection
- Hot-switch cutover helper

Gardener is the default `maintenance_backend: :gardener`.

## Pick one maintainer per table

New date-keyed OLTP table — create with pg_party or SQL; maintain with Gardener sliding window.

Plain monthly series when the extension is OK — create with pg_party or SQL; maintain with partman only (`maintenance_backend: :pg_partman`).

Migrating from premake-only cron — keep existing DDL; use Gardener after `premake_monthly` bridge, then upgrade template.

partman premake plus custom tail layout — create with pg_party or SQL; maintain with `maintenance_backend: :hybrid_layout_only` (gardener layout only; partman premake).

## Hybrid mode

`maintenance_backend: :hybrid_layout_only` means:

- pg_partman owns premake and simple retention on `partman.part_config`
- Gardener runs tail rebalance, default drain, and gap repair only
- Gardener must not create the same monthly bounds partman already premakes

On register, Gardener probes `partman.part_config` and warns when:

- `maintenance_backend: :gardener` but partman also lists the parent
- `maintenance_backend: :pg_partman` but partman has no row
- `hybrid_layout_only` but partman has no row

## Legacy premake template

`Templates.premake_monthly` is a stepping stone from cron premake jobs.

- Ensures current month through `premake_months` ahead exist
- Drains default
- Does not run sliding-window tail rebalance

Migrate to `sliding_window_monthly` when default stays empty and horizon warnings clear.

## Related

- [decision_flow.md](decision_flow.md) — when to partition and which layout
- [configuration.md](configuration.md) — `maintenance_backend` and per-table registry
- [background_job.md](background_job.md) — schedule gardener runs
- [cutover.md](cutover.md) — creation through hot switch
- [related_postgres_tooling.md](related_postgres_tooling.md) — ankane tools; pgslice hot-switch detail in [cutover.md](cutover.md#lessons-from-pgslice)

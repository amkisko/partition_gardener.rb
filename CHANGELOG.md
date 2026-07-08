# CHANGELOG

## 0.2.0 (2026-07-06)

- Add configuration, background job, and CLI guides under `docs/`
- Add `partition_gardener` CLI with `plan`, `audit`, and `apply` for dry-run planning, health checks, and maintenance
- Add dry-run plan reports with gap detection and JSON schema export
- Add hot-switch migration helpers for zero-downtime cutover to partitioned tables
- Add layout recommendations for date partition keys
- Add per-table advisory locks during maintenance runs
- Add `continue_on_error` so one failing table does not block the rest
- Add run summaries with per-table duration, plan signature, and rows moved
- Add sliding-window retention policies with optional concurrent detach
- Add incremental rebalance and resume checkpoints after partial rebalance failure
- Add per-table statement timeouts during maintenance
- Add conflict-index verification before row moves
- Add durable run records when ActiveRecord is available
- Fix default advisory lock to transaction-scoped try-lock and skip locked tables
- Fix hash partition layouts to omit unsupported default partitions
- Fix hot-switch delta sync when there are no updatable columns
- Fix batch row moves to avoid `ON CONFLICT` stalls during rebalance

## 0.1.0 (2026-07-05)

- Initial release of PostgreSQL partition lifecycle maintenance
- Add templates for sliding-window monthly, calendar year, integer window, list split, composite, and hash layouts
- Add injectable notifier, connection, statement timeout, and today resolver
- Add Rails railtie for ActiveRecord connection defaults

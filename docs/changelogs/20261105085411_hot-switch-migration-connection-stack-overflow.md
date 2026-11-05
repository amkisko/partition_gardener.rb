# Hot-switch migrations including HotSwitchConcern could stack-overflow on Rails 8 when any Migration DSL method ran through DefaultStrategy.

## Participants

Andrei Makarov (@amkisko)

## Decisions

- Rename the concern's connection helper to gardener_connection so ActiveRecord::Migration#connection stays public.
- Keep hot-switch SQL on gardener_connection.execute (configured resolver), not Migration#execute.

## Effects

- SystemStackError with repeating `-- connection(nil)` no longer occurs for create_table after include.
- Cut into CHANGELOG under `## 0.3.8 (2026-11-05)`.

## Next

- Commit, tag `0.3.8`, push, and run `make release`.

## Source

- docs/issues/20261105085411_hot-switch-migration-connection-stack-overflow.md
- docs/reviews/20261105085411_engineering-audit-hot-switch-connection.md

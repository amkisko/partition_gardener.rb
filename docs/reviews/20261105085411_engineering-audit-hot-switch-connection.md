# Engineering audit of HotSwitchConcern connection handling after a reported SystemStackError on Rails 8 multi-database migrate.

## Participants

Andrei Makarov (@amkisko)

## Decisions

- Claims from the incident note were checked only against this repository and installed ActiveRecord 8.1 sources; no consumer app tree was opened.
- Root cause is a private connection method on HotSwitchConcern that shadows Migration#connection. DefaultStrategy calls migration.connection with an explicit receiver; that hits Migration#method_missing, which asks execution_strategy.respond_to?, which calls connection again.
- The `-- connection(nil)` spam is Rails format_arguments on an empty argument list (last is nil), not a literal nil argument from the host.
- connected_to_stack can appear when the configured resolver calls ActiveRecord::Base.connection; it is on the stack, not the recursion engine.
- Multi-database migrate context is where the host hit the bug; the overflow reproduces without a second database once the concern is included and Migration DSL runs.
- schema.rb dropping PARTITION BY is a separate Rails schema dump limitation; out of scope for this connection fix.
- Boundary and control mode skipped: library SQL helpers, no physical actuators.
- Product-surface, privacy, learned-systems, lineage modes skipped: no person-facing product surface in this change.
- Resource and budget: overflow is unbounded stack growth until SystemStackError; fix removes the recursive path (measured: create_table completes after fix).
- Trace and identification: verbose migration lines are local process stdout only; no new identifiers emitted by the fix.

## Effects

- Finding F1 confirmed and fixed: private connection override vs DefaultStrategy recursion.
- Finding F2 confirmed and fixed: gardener_connection prefers Migration @connection when exec_migration set it, else configuration.connection_resolver, so multi-db migrate SQL stays on the migration-scoped adapter.
- Regression specs added; rails8ruby34 and rails72 focused suites green for hot_switch_concern_spec.
- Second pass: no other HotSwitchConcern methods shadow Migration DSL entry points (execute, transaction, say).

## Next

- Publish `0.3.8` after commit on a clean tree (`make release`).
- Cutover docs do not imply overriding `Migration#connection`; no doc change required for this fix.

## Source

- lib/partition_gardener/migration/hot_switch_concern.rb
- lib/partition_gardener/rails.rb
- lib/partition_gardener/configuration.rb
- spec/partition_gardener/migration/hot_switch_concern_spec.rb
- activerecord-8.1.3 lib/active_record/migration/default_strategy.rb

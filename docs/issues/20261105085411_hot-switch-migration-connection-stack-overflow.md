# Hot-switch migrations that include HotSwitchConcern abort with SystemStackError on Rails 8 while printing many `-- connection(nil)` lines. Local RANGE partition DDL can succeed; the failure is in the migration connection path.

## Participants

Andrei Makarov (@amkisko)

## Decisions

- Stop overriding ActiveRecord::Migration#connection from HotSwitchConcern.
- Route hot-switch SQL through a private gardener_connection helper and adapter execute, so Strong Migrations still does not see Migration#execute.
- Prefer Migration @connection when present (multi-db migrate scope); otherwise use PartitionGardener.configuration.connection.
- Keep Migration#connection public so DefaultStrategy can resolve the adapter without entering method_missing recursion.

## Effects

- Reproduced before the fix: including HotSwitchConcern, then create_table or execution_strategy.respond_to?(:create_table), overflows through DefaultStrategy#connection -> Migration#method_missing -> respond_to_missing? -> connection again.
- After the fix: same path completes; Migration#connection owner stays ActiveRecord::Migration.
- Spec coverage added for the non-recursion contract; focused hot-switch specs pass on Rails 7.2 and Rails 8.1 appraisals.

## Next

- Publish `0.3.8` (`make release` after commit and clean tree).
- Host apps pinned on 0.3.7 need `0.3.8` or an equivalent local patch before hot-switch cutover migrations that also use Migration DSL.

## Source

- lib/partition_gardener/migration/hot_switch_concern.rb
- activerecord migration DefaultStrategy#connection
- docs/reviews/20261105085411_engineering-audit-hot-switch-connection.md
- docs/changelogs/20261105085411_hot-switch-migration-connection-stack-overflow.md

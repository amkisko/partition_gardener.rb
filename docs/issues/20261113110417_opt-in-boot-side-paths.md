# Default require loaded CLI, HotSwitch, Railtie (when Rails::Railtie was defined), and an Integer duration monkey-patch without an explicit host opt-in.

## Participants

Andrei Makarov (@amkisko)

## Decisions

- Keep maintenance/register/run on the default require so existing jobs and initializers keep working.
- Make Railtie, CLI, HotSwitchConcern, and stdlib Integer helpers explicit requires.
- Railtie uses `config.partition_gardener.auto_configure` (default true once the railtie is loaded) so hosts can require the railtie file without overwriting resolvers.
- Record boot footprint with `usr/reports/boot_footprint.rb` and a subprocess contract spec.

## Effects

- Before (this machine, 20 cold subprocesses): mean 37.64 ms, 55 gardener files; Integer duration patch installed when Active Support Duration was absent; CLI and HotSwitch constants always defined; Railtie auto-loaded whenever `Rails::Railtie` was already defined.
- After (same method, 20 cold subprocesses): mean 34.75 ms, 52 gardener files; CLI / HotSwitch / Railtie / stdlib_extensions absent from default require.
- Absolute time win is small while the maintenance stack stays eager; the contract win is consent (no silent Railtie or monkey-patch).
- Specs that use CLI or HotSwitch require those files directly.

## Next

- Host apps that relied on silent Railtie defaults must add `partition_gardener/railtie` to the Gemfile require list (or set resolvers in an initializer, which many already do).
- Hot-switch migrations must `require "partition_gardener/migration/hot_switch_concern"`.
- Optional later: further slim the default require if app boot budgets demand it; keep that behind an explicit runtime entry point rather than silent autoload.

## Source

- lib/partition_gardener.rb
- lib/partition_gardener/railtie.rb
- lib/partition_gardener/rails.rb
- lib/partition_gardener/stdlib_extensions.rb
- spec/partition_gardener/boot_footprint_spec.rb
- usr/reports/boot_footprint.rb
- docs/changelogs/20261113110417_opt-in-boot-side-paths.md

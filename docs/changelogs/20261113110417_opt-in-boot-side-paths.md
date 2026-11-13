# Default require no longer pulls Railtie, CLI, HotSwitch, or Integer duration helpers.

## Participants

Andrei Makarov (@amkisko)

## Decisions

- Treat side paths as opt-in requires; document Gemfile and migration require lines.
- Keep `auto_configure` on the railtie so requiring the railtie remains one clear consent switch.

## Effects

- Apps boot without gem Railtie configuration unless they require `partition_gardener/railtie`.
- Cutover migrations and the CLI load only when those entry points are required.
- Boot footprint report and contract spec capture the default-require inventory.

## Next

- Note the host migration steps under Unreleased until the next patch cut.

## Source

- docs/issues/20261113110417_opt-in-boot-side-paths.md

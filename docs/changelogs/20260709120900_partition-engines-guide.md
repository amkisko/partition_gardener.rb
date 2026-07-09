## Participants

Andrei Makarov, agent-assisted release prep.

## Decisions

Cut patch release 0.3.1 for documentation shipped after 0.3.0. No runtime or API changes.

## Effects

Added product-facing bullets to CHANGELOG.md and bumped lib/partition_gardener/version.rb to 0.3.1.

## Next

Run make release on trunk/0.3.1 after merge to main, or release from this branch per maintainer workflow.

## Source

Commits since tag 0.3.0:

- 67ffcb1 Add documentation for partition engines and related patterns
- 7d91d4a Add coverage directory creation in GitHub Actions workflow (CI only; omitted from CHANGELOG)

New file docs/partition_engines.md maps Gardener's portable patterns (sliding window, premake, default drain, heat splits, keyset rebalance, hot-switch) to other database engines. README and existing guides cross-link the page.

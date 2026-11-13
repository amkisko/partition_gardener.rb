# Engineering audit and release preparation

## Participants

Andrei Makarov (@amkisko)

## Decisions

- Continue on main. Do not commit, tag, push, or publish in this session.
- Cut patch release version 0.3.9 for opt-in boot side paths and the partman probe transaction fix. Set the CHANGELOG heading date to 2026-11-13.
- Re-check lint, executable coverage, workflow YAML parse, package boundaries, and cold-require cost after the cut.

## Effects

- Bump `PartitionGardener::VERSION` and path-gem lockfiles to 0.3.9. Move the Unreleased bullets under `## 0.3.9 (2026-11-13)`.
- Fix boot footprint counting so paths under a checkout named `partition_gardener.rb` (including `vendor/bundle`) do not inflate `gardener_files`. Loose filter reported 68; `lib/partition_gardener` filter reports 52 and restores the `< 55` contract.
- Publish GitHub release body from the matching `CHANGELOG.md` section (`gh release create --notes-file`), not commit auto-notes.
- Final serial JSON report: 196 examples, 0 failures with `INTEGRATION=1` and PostgreSQL; no pending examples. Parallel polyrun with five workers: exit 0.
- Required project checks passed: rubocop (84 files, no offenses), rbs validate, `INTEGRATION=1` polyrun parallel-rspec. Environment: Ruby 4.0.2, `BUNDLE_PATH=vendor/bundle`.
- `release_spec`: 2 examples, 0 failures.
- Build the gem, verify it with `Gem::Package#verify`, and confirm the changelog heading matches version 0.3.9. Compressed package: 124928 bytes; source payload: 433997 bytes across 116 packaged paths. These are compressed versus uncompressed sizes, not interchangeable quantities.
- Cold process measurement on macOS arm64 with `/usr/bin/time -p` and `bundle exec ruby -Ilib`: 0.17 CPU seconds, 0.25 elapsed seconds. Peak RSS via `/usr/bin/time -l`: 30687232 bytes. Local smoke ceilings: 1 MiB compressed gem, 128 MiB RSS, 2 CPU seconds. Measured gem size, RSS, and CPU fit those ceilings. CPU seconds are the energy proxy; electricity use was not measured.
- Parse every workflow YAML, verify lockfile own-gem versions at 0.3.9, and run `git diff --check`. All passed. RubyGems has no `0.3.9` yet.

## Next

- Commit, tag 0.3.9, push, and publish remain operator steps; this session did not run them. When the tree is clean, `make release` runs gem push, tag, and GitHub release.
- Host apps that relied on silent Railtie defaults must require `partition_gardener/railtie`. Hot-switch migrations must require `partition_gardener/migration/hot_switch_concern`.
- Hosted GitHub Actions and the complete supported Ruby/framework matrix were not executed locally beyond the default Gemfile path used by `make test`.
- Scope limits: production traffic, production database size and query plans, external service retention, and co-located resource interference were not measured. The local byte/CPU results do not establish those properties.
- Trace review follows local file/log and protocol emissions. No live customer identities or credentials were used. Data retention and deletion in embedding applications remain host contracts.
- Database-boundary mode applies to PostgreSQL maintenance DDL and the register-time partman catalog probe.

## Source

- AGENTS.md
- .agents/skills/engineering-audit/SKILL.md
- .agents/skills/changelog-update/SKILL.md
- CHANGELOG.md
- Makefile
- spec/README.md
- docs/changelogs/20261113130745_cut-patch-release-0-3-9.md
- docs/changelogs/20261113110417_opt-in-boot-side-paths.md
- docs/changelogs/20261113104337_partman-probe-aborts-open-transactions.md
- docs/issues/20261113110417_opt-in-boot-side-paths.md
- docs/issues/20261113104337_partman-probe-aborts-open-transactions.md

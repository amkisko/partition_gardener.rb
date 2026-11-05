# Engineering audit and release preparation

## Participants

Andrei Makarov (@amkisko)

## Decisions

- Continue on main while preserving uncommitted work. Do not commit, tag, push, or publish in this session.
- Cut patch release version 0.3.8 for the Rails 8 hot-switch `SystemStackError` fix. Set the CHANGELOG heading date to 2026-11-05.
- Re-check lint, executable coverage, workflow YAML parse, package boundaries, and cold-require cost after the cut.

## Effects

- Bump `PartitionGardener::VERSION` and path-gem lockfiles to 0.3.8. Move the Unreleased bullet under `## 0.3.8 (2026-11-05)`.
- Fix rubocop offenses in `hot_switch_concern_spec` introduced by the connection helper rewrite (`RSpec/InstanceVariable`, `Layout/EmptyLineBetweenDefs`).
- Final serial JSON report: 190 examples, 0 failures with `INTEGRATION=1` and PostgreSQL on port 5432; no pending examples. Parallel polyrun with five workers: exit 0.
- Required project checks passed: rubocop (116 files, no offenses), rbs validate, `INTEGRATION=1` polyrun parallel-rspec. Environment: Ruby 4.0.2, `BUNDLE_PATH=vendor/bundle`.
- `release_spec`: 2 examples, 0 failures.
- Build the gem, verify it with `Gem::Package#verify`, and confirm the changelog heading matches version 0.3.8. Compressed package: 121344 bytes; source payload: 421347 bytes across 109 packaged paths. These are compressed versus uncompressed sizes, not interchangeable quantities.
- Cold process measurement on macOS arm64 with `/usr/bin/time -p` and `bundle exec ruby -Ilib`: 0.18 CPU seconds, 0.26 elapsed seconds. Peak RSS via `/usr/bin/time -l`: 31293440 bytes. Local smoke ceilings: 1 MiB compressed gem, 128 MiB RSS, 2 CPU seconds. Measured gem size, RSS, and CPU fit those ceilings. CPU seconds are the energy proxy; electricity use was not measured.
- Parse every workflow YAML, verify lockfile own-gem versions at 0.3.8, and run `git diff --check`. All passed.

## Next

- Commit, tag 0.3.8, push, and publish remain operator steps; this session did not run them. When the tree is clean, `make release` runs gem push, tag, and GitHub release.
- Hosted GitHub Actions and the complete supported Ruby/framework matrix were not executed locally beyond the default Gemfile path used by `make test`.
- Scope limits: production traffic, production database size and query plans, external service retention, and co-located resource interference were not measured. The local byte/CPU results do not establish those properties.
- Trace review follows local file/log and protocol emissions. No live customer identities or credentials were used. Data retention and deletion in embedding applications remain host contracts.
- Learned-system training/evaluation and cloud deployment modes do not apply to this library tree. Database-boundary mode applies to PostgreSQL maintenance DDL and hot-switch migration SQL. The library has no independent production health endpoint to assess.

## Source

- AGENTS.md
- .agents/skills/engineering-audit/SKILL.md
- .agents/skills/changelog-update/SKILL.md
- CHANGELOG.md
- Makefile
- spec/README.md
- docs/reviews/20261105085411_engineering-audit-hot-switch-connection.md
- docs/changelogs/20261105090326_cut-patch-release-0-3-8.md
- docs/changelogs/20261105085411_hot-switch-migration-connection-stack-overflow.md

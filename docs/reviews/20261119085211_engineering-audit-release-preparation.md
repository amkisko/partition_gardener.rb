# Engineering audit and release preparation

## Participants

Andrei Makarov

## Decisions

- Continue on main. Do not commit, tag, push, or publish in this session.
- Cut patch release version 0.3.10 for the monthly premake default-overlap create fix. Set the CHANGELOG heading date to 2026-11-19.

## Effects

- Bump `PartitionGardener::VERSION` and path-gem lockfiles to 0.3.10. Move the Unreleased bullet under `## 0.3.10 (2026-11-19)`.
- Final serial JSON report: 201 examples, 0 failures with `INTEGRATION=1` and PostgreSQL; no pending examples. Parallel polyrun with five workers: exit 0.
- Required project checks passed: rubocop (121 files, no offenses), rbs validate, `INTEGRATION=1` polyrun parallel-rspec. Environment: Ruby 4.0.2.
- `release_spec`: 5 examples, 0 failures.
- Build the gem, verify it with `Gem::Package#verify`, and confirm the changelog heading matches version 0.3.10. Compressed package: 128000 bytes across 122 packaged paths.
- Cold process measurement on macOS arm64 with `/usr/bin/time -p` and `bundle exec ruby -Ilib`: 0.19 CPU seconds, 0.33 elapsed seconds. Peak RSS was not captured in this run (`time -l` failed under the agent sandbox). Local smoke ceilings: 1 MiB compressed gem, 128 MiB RSS, 2 CPU seconds. Measured gem size and CPU fit those ceilings. CPU seconds are the energy proxy; electricity use was not measured.
- Parse every workflow YAML, verify lockfile own-gem versions at 0.3.10, and run `git diff --check`. All passed. RubyGems has no `0.3.10` yet.

## Next

- Commit, tag 0.3.10, push, and publish remain operator steps; this session did not run them. When the tree is clean, `make release` runs gem push, tag, and GitHub release.
- Host apps that added a one-off preparation step before monthly premake `run!` can drop it once this version is locked.
- Hosted GitHub Actions and the complete supported Ruby/framework matrix were not executed locally beyond the default Gemfile path.
- Scope limits: production traffic, production database size and query plans, external service retention, and co-located resource interference were not measured. The local byte/CPU results do not establish those properties.
- Trace review follows local file/log and protocol emissions. No live customer identities or credentials were used. Data retention and deletion in embedding applications remain host contracts.
- Database-boundary mode applies to PostgreSQL maintenance DDL for monthly premake create when the default partition already holds overlapping rows.

## Source

- AGENTS.md
- .agents/skills/engineering-audit/SKILL.md
- .agents/skills/changelog-update/SKILL.md
- CHANGELOG.md
- Makefile
- docs/changelogs/20261119085211_cut-patch-release-0-3-10.md
- docs/changelogs/20261119083632_premake-monthly-default-overlap-create.md
- docs/issues/20261119083632_premake-monthly-default-overlap-create.md

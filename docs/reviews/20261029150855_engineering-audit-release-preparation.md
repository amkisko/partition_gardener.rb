# Engineering audit and release preparation

## Participants

Andrei Makarov (@amkisko)

## Decisions

- Continue on main while preserving uncommitted work. Do not commit, tag, push, or publish.
- Keep release version 0.3.7. Set the CHANGELOG heading date to 2026-10-29. RubyGems still lists 0.3.6 as the latest published version.
- Re-check correctness, executable coverage, workflow triggers and permissions, package boundaries, resource cost, and database-boundary behavior after the prior release-prep pass.

## Effects

- Enable `pull_request` on the test workflow, keep token permissions at `contents: read`, and cancel superseded runs.
- Set the `CHANGELOG.md` heading for 0.3.7 to 2026-10-29 and align the cut note under `docs/changelogs/`.
- Final serial JSON report: 188 examples, 0 failures with `INTEGRATION=1` and PostgreSQL on port 5432; no pending examples. Parallel polyrun with five workers: exit 0.
- Required project checks passed: rubocop (116 files, no offenses), rbs validate, `INTEGRATION=1` polyrun parallel-rspec. Environment: Ruby 4.0.2, `BUNDLE_PATH=vendor/bundle`.
- `release_spec`: 2 examples, 0 failures (EOF refuses gem push; Enter accepts the displayed default with system execution replaced).
- Build the gem, verify it with `Gem::Package#verify`, and confirm the changelog heading matches version 0.3.7. Compressed package: 117760 bytes; source payload: 495104 bytes across 104 packaged paths. These are compressed versus uncompressed sizes, not interchangeable quantities.
- Cold process measurement on macOS arm64 with `/usr/bin/time -p` and `bundle exec ruby -Ilib`: 0.17 CPU seconds, 0.26 elapsed seconds. Peak RSS via `/usr/bin/time -l` was unavailable in this session (`sysctl kern.clockrate` refused). Prior release-prep peak RSS on the same require path was 31817728 bytes. Local smoke ceilings: 1 MiB compressed gem, 128 MiB RSS, 2 CPU seconds. Measured gem size and CPU fit those ceilings. CPU seconds are the energy proxy; electricity use was not measured.
- Parse every workflow YAML, verify lockfile own-gem versions at 0.3.7, and run `git diff --check`. All passed.

## Next

- Commit, tag 0.3.7, push, and publish remain operator steps; this session did not run them. When the tree is clean, `make release` runs gem push, tag, and GitHub release.
- Hosted GitHub Actions and the complete supported Ruby/framework matrix were not executed locally beyond the default Gemfile path used by `make test`.
- Re-measure peak RSS with `/usr/bin/time -l` outside the restricted session if a fresh number is required before publish.
- Scope limits: production traffic, production database size and query plans, external service retention, and co-located resource interference were not measured. The local byte/CPU results do not establish those properties.
- Trace review follows local file/log and protocol emissions. No live customer identities or credentials were used. Data retention and deletion in embedding applications remain host contracts.
- Learned-system training/evaluation and cloud deployment modes do not apply to this library tree. Database-boundary mode applies to PostgreSQL maintenance DDL and checkpoint resume. The library has no independent production health endpoint to assess.

## Source

- AGENTS.md
- .agents/skills/engineering-audit/SKILL.md
- .agents/skills/changelog-update/SKILL.md
- CHANGELOG.md
- Makefile
- spec/README.md
- docs/reviews/20261028075216_engineering-audit-release-preparation.md
- docs/reviews/20261021220000_engineering-audit-0-3-7.md
- docs/changelogs/20261021220000_cut-patch-release-0-3-7.md

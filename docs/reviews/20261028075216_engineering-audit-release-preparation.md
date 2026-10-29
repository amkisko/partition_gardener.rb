# Engineering audit and release preparation

## Decisions

- Continue on main while preserving the pre-existing uncommitted changes. Do not commit, tag, push, or publish.
- Retain release version 0.3.7. Reconcile root and appraisal PATH metadata without updating third-party dependency versions.
- Review correctness, executable coverage, workflow triggers and permissions, package boundaries, resource cost, and trace/identity boundaries. Re-audit the changed paths after corrections.

## Effects

- Correct the resume integration fixture's initial expectation: the source rows initially belong to the attached current partition, and the hot monthly partition exists after rebalance.
- Restore the required lint gate by combining adjacent boundary stubs. Verify all integration examples against an isolated PostgreSQL server, including the existing rebalance and hot-switch changes.
- Synchronize the own-gem PATH version in the root and appraisal lockfiles to 0.3.7, enable pull-request tests, and restrict workflow permissions to contents: read.
- Fix the release confirmation guard in usr/bin/release.rb so EOF refuses publication. An explicit Enter still selects the displayed default. The process-boundary regression test executes the release script with command execution replaced at the operating-system boundary; no publication command runs against a real service. The shared regression was observed first in Favorites: 2 examples, 1 failure before correction and 2 examples, 0 failures after correction. The release specs pass in every repository.
- Final serial JSON report: 188 examples, 0 failures with INTEGRATION=1 and PostgreSQL; no pending integration examples.
- Required project checks passed: DATABASE_URL=postgres://postgres@127.0.0.1:55432/partition_gardener_test make test. Environment: Ruby 4.0.2, BUNDLE_PATH=vendor/bundle; the installed native extensions require that Ruby build.
- Build the gem, verify it with Gem::Package#verify, and check that the changelog heading matches the gem version. Final package measurements are recorded in the session output; this gem includes the review note itself.
- Cold process measurement on macOS arm64 with /usr/bin/time -l and bundle exec ruby -Ilib: 0.35 CPU seconds, 0.7 elapsed seconds, 31817728 peak RSS bytes. Favorites loads Rails before the engine. Local smoke ceilings: 1 MiB compressed gem, 128 MiB RSS, 2 CPU seconds. All measured values fit those ceilings. CPU seconds are the energy proxy; electricity use was not measured.
- Parse every workflow YAML, verify lockfile own-gem versions, and run git diff --check. All passed. All six assigned repositories remain on main.

## Next

- No confirmed correction remains in the reviewed changes. Hosted GitHub Actions and the complete supported Ruby/framework matrix were not executed locally.
- Scope limits: production traffic, production database size and query plans, external service retention, and co-located resource interference were not measured. The local byte/RSS/CPU results do not establish those properties.
- Trace review follows local file/log and protocol emissions. No live customer identities or credentials were used. Data retention and deletion in embedding applications remain host contracts.
- Learned-system training/evaluation and cloud deployment modes do not apply to these library trees. Native memory-boundary mode applies to Polyrun's extension; browser presentation applies to Favorites; HTTP/identity and message companions apply only to repositories that expose those boundaries. Libraries have no independent production health endpoint to assess.

## Source

- AGENTS.md
- .agents/skills/engineering-audit/SKILL.md
- .agents/skills/changelog-update/SKILL.md
- CHANGELOG.md
- Makefile
- spec/README.md

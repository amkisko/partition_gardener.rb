# Relock appraisal graphs for json advisory

## Participants

Andrei

## Decisions

Appraisal lockfiles are part of the CI install graph. After 0.3.3 they must pin partition_gardener 0.3.3 and json 2.21.2 so frozen bundle install and bundle-audit both pass. The dependency audit workflow scans Gemfile.lock and *.gemfile.lock.

## Effects

Relocked gemfiles/rails72.gemfile.lock, gemfiles/rails8ruby34.gemfile.lock, and gemfiles/rails8ruby4.gemfile.lock. Widened the find in .github/workflows/dependency-audit.yml.

## Next

Merge the patch so main test and dependency audit jobs install a consistent graph.

## Source

Triggered by failing Dependency audit and test workflows after the 0.3.3 merge. Advisory note: usr/docs/dependencies/20260813144516_json-cve-2026-71847.md.

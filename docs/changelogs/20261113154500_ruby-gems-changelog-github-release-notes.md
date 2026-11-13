# Propagate CHANGELOG GitHub release notes across amkisko Ruby gems.

## Participants

Andrei Makarov (@amkisko)

## Decisions

- Same contract as partition_gardener and pray `github.sh`: release body from the matching `CHANGELOG.md` section; always pass `--title` with the version/tag.
- Batch-update every amkisko gem that uses `usr/bin/release.rb` plus `usr/lib/release_version_check.rb`.
- Skip `annotator` (app zip release, already has `--title`, still on `--generate-notes`).
- Do not create per-language GitHub releases for pray; that tree already publishes one `vX.Y.Z` release from root CHANGELOG.

## Effects

- 24 gems received `changelog_notes_for` / `require_changelog_notes!` and `gh release create VERSION --title VERSION --notes-file tmp/github-release-notes.md`.
- 5 gems with `spec/release_spec.rb` assert `--title` and `--notes-file` (plus partition_gardener).
- Changelog reads use `File.foreach(..., encoding: "UTF-8")`.
- `lepiota.rb` still has `## 0.1.0 (Unreleased)` while `VERSION` is `0.1.0`; `require_changelog_notes!` will refuse until that heading is cut to a dated release section (same class of failure as the existing version heading check).

## Next

- Commit each gem repo on its own (operator).
- Optional later: annotator notes-file; Elixir/Rust/Crystal/CLI scripts; repair empty historical GitHub release names with `gh release edit`.

## Source

- `usr/bin/release.rb` / `usr/lib/release_version_check.rb` in the updated gem checkouts under `amkisko/`
- `kiskolabs/pray/scripts/release/github.sh`
- `docs/changelogs/20261113132159_github-release-title-from-version.md`

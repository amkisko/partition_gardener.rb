# GitHub release create with --notes-file left release name empty.

## Participants

Andrei Makarov (@amkisko)

## Decisions

- Pass `--title` with the gem version whenever creating a release from changelog notes.
- Repair the published `0.3.9` release name in place (`gh release edit`); do not re-cut the gem.

## Effects

- `gh release create` without `--generate-notes` does not fill `name`; empty name shows as "undefined" in Discord/Slack GitHub notifications.
- `usr/bin/release.rb` now runs `gh release create VERSION --title VERSION --notes-file ...`.
- Live release `0.3.9` name set to `0.3.9` (was empty string).

## Next

- Commit the release script and spec fix on `main`.

## Source

- usr/bin/release.rb
- spec/release_spec.rb
- https://github.com/amkisko/partition_gardener.rb/releases/tag/0.3.9

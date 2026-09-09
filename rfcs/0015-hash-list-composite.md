# RFC 0015: Hash, list, and composite layouts

- Feature Name: hash-list-composite
- Type: Standards Track
- Status: Stable
- Created: 2026-09-09
- Author: Andrei Makarov
- Stakeholders: project maintainers
- Relates: RFC 0002, RFC 0004

## Summary

Specify hash remainder children without a default, Ruby-only list branches with a default, and composite trees as separately registered gardener tables. JSON import MUST fail for list and composites.

## Motivation

HASH, LIST, and nested PARTITION BY are not the sliding window (RFC 0003). Mixing them into one registry object would hide the extra parent names operators must plan.

## Guide-level explanation

`hash_branches` with modulus 32 creates `events_h_00` … `events_a_31` (hot prefix `h`, archive prefix `a`) and does not create `{table}_default`. `list_split` in Ruby registers named branches plus default. A list-then-range tree registers the list parent and each range subtree as its own gardener table.

## Reference-level explanation

### Hash

Layout `hash_branches`. Default modulus 32. Names `{table}_h_%02d` (hot remainder) and `{table}_a_%02d` (archive remainder). `default_partition_required?` is false; do not plan `{table}_default`. JSON import MAY load this layout (RFC 0004).

### List

Layout `list_split` is Ruby-only. Default is required. Each branch has `name`, `value`, and `predicate` with `eq`, `ne`, `is_null`, or `is_not_null`. Child name `{table}_{branch.name}`. JSON import MUST raise `ArgumentError` with `layout #{layout.inspect} is not supported in JSON import (supported: …; composite and list_split require Ruby registration)`.

### Composites

Supported compositions: `composite_list_hash`, `composite_list_range` / `list_range`, `composite_range_hash`, `composite_range_list`. Each subtree is a separate registered table with its own `table_name`. JSON import MUST fail with that same `ArgumentError` for those layout names.

Tail occupancy (RFC 0002) is a date-range walk. Hash and list `tail_slot_name?` is false.

### Fail modes

JSON `layout` `list_split` or a composite name MUST NOT register a partial hash of keys. Hash MUST NOT emit a default child. List without default fails `RequiresDefaultPartition`.

## Implementation notes

`lib/partition_gardener/strategy/hash_branches.rb`, `list_split.rb`, composite strategy files. Import reject: `ConfigDocument`.

## Registrar

Layouts `hash_branches`, `list_split`, `composite_list_hash`, `composite_list_range`, `list_range`, `composite_range_hash`, `composite_range_list`. Hash prefixes `h` and `a`. List predicates `eq`, `ne`, `is_null`, `is_not_null`.

## Drawbacks

Operators must remember two (or more) registry rows for one logical tree. Hash without default means a modulus change orphans remainders.

## Rationale and alternatives

Separate table names match how PostgreSQL names subpartitioned children. Rejected: one JSON object that expands composites at import.

## Prior art

PostgreSQL HASH and LIST. Nested `PARTITION BY`.

## Unresolved questions

Whether list predicates should enter JSON without opening composites (RFC 0004).

## Future possibilities

JSON for `list_split` only. Occupancy-like remainder reuse if modulus changes.

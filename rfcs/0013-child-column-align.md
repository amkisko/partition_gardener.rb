# RFC 0013: Child column align

- Feature Name: child-column-align
- Type: Standards Track
- Status: Stable
- Created: 2026-09-09
- Author: Andrei Makarov
- Stakeholders: project maintainers
- Relates: RFC 0005, RFC 0012

## Summary

Specify additive alignment of ordinary columns from parent onto children. Identity and generated columns stay out. Missing columns are an audit warning.

## Motivation

`ALTER TABLE parent ADD COLUMN` does not always appear on every child the operator already attached. Attach or insert then fails with a column mismatch that is hard to read as a gardener concern.

## Guide-level explanation

With default `align_child_columns: true`, `run!` adds `notes text` to `events_2026_08` when the parent has that column and the child does not. Audit prints `child events_2026_08 is missing column notes from parent events` until aligned. `align_child_columns: false` fails fast instead of adding.

## Reference-level explanation

Align copies name, type, collation, default, and NOT NULL for ordinary columns. Skip identity and generated columns. PostgreSQL rejects the whole `ADD COLUMN` if existing rows cannot satisfy NOT NULL; that error is a run failure, not a partial add.

Default `align_child_columns` is true. False: do not ALTER children; abort that table's align path (fail fast).

Audit warning format is RFC 0005: `child {name} is missing column {columns} from parent {table}`.

### Fail modes

NOT NULL add on a populated child that has NULLs for that semantic MUST fail the statement. Unique indexes and check constraints are not created by align. Do not drop extra child columns.

## Implementation notes

`lib/partition_gardener/child_column_align.rb`.

## Registrar

`align_child_columns`. Audit warning sentence above.

## Drawbacks

Additive-only cannot fix a child that has a wider type. Fail-fast false still needs a migration the operator writes.

## Rationale and alternatives

Copying parent ordinary columns is the smallest attach repair. Rejected: rewriting child tables. Rejected: aligning indexes in the same RFC.

## Prior art

PostgreSQL partition column matching rules. Manual `ALTER TABLE child ADD COLUMN`.

## Unresolved questions

Whether generated columns should copy as stored expressions in a later RFC.

## Future possibilities

Index align. A preview list of ADD COLUMN statements in `plan`.

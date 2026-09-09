# RFC 0004: Registry JSON

- Feature Name: registry-json
- Type: Standards Track
- Status: Stable
- Created: 2026-09-09
- Author: Andrei Makarov
- Stakeholders: project maintainers
- Relates: RFC 0001, RFC 0003

## Summary

Specify the portable table registration file: required keys, allowed keys, importable layouts, and the trust boundary for `partition_key_column`. Ruby templates remain the path for list and composite layouts.

## Motivation

CLI `--registry` and `ConfigDocument.load_registry_file!` load operator JSON. Extra keys, unknown layouts, or untrusted SQL in `partition_key_column` would change routing without a numbered contract.

## Guide-level explanation

A file may be one table object, an array of table objects, or `{ "tables": [ ... ] }`. `partition_gardener --registry config/partition_garden.json audit --all` loads it and replaces the in-memory registry. Unknown keys fail the load. `list_split` and composite layouts fail JSON import; register those in Ruby.

## Reference-level explanation

### Entry shape

Each table object MUST include `table_name`, `layout`, `partition_key_column`, and `conflict_key`. `conflict_key` is a non-empty array of non-empty strings. Additional properties are forbidden. Allowed optional keys match `docs/schemas/partition_garden.schema.json`: `bucket`, `active_*`, `premake_months`, `split_row_threshold`, `move_batch_size`, `statement_timeout` (seconds), retention fields, `align_child_columns`, `hash_modulus`, `maintenance_backend`, `incremental_rebalance`, `run_record_enabled`, `analyze_after_rebalance`.

### Layouts

JSON import MAY load `sliding_window`, `rolling_current`, `calendar_year`, `premake_monthly`, `integer_window`, `hash_branches`. `bucket` on sliding window is `day`, `week`, `month`, `quarter`, or `year`. Other layouts MUST raise at import.

Ruby-only keys `partition_name_format`, `partition_definition`, and `extract_partition_identifier` MUST NOT appear in JSON.

### Trust

Registry files are operator-controlled, not end-user input. `partition_key_column` is embedded in generated SQL as a trusted expression. List-branch filters belong in Ruby `predicate` hashes. Do not load registry JSON from untrusted upload paths.

### Fail modes

Missing required keys, unknown keys, empty `table_name` or `partition_key_column`, a non-array `conflict_key`, an unsupported layout, or a bad `maintenance_backend` MUST raise `ArgumentError` and MUST NOT register a partial file after `Registry.reset!`.

## Implementation notes

Schema: `docs/schemas/partition_garden.schema.json`. Loader: `lib/partition_gardener/config_document.rb`.

## Registrar

`ConfigDocument.load_registry_file!`, `ConfigDocument.export`, `ConfigDocument.export_all`. CLI flag `--registry`.

## Drawbacks

Operators cannot round-trip list or composite trees through JSON. Extra unknown keys fail closed instead of ignoring.

## Rationale and alternatives

A closed key set keeps portable files reviewable. Rejected: accepting lambdas in JSON. Rejected: fetching the schema `$id` URL at runtime; the gem validates the bundled copy.

## Prior art

JSON Schema draft 2020-12 `additionalProperties: false`. pg_partman `part_config` is a SQL catalog, not a file.

## Unresolved questions

Whether JSON import should grow `list_split` predicates without opening composite trees.

## Future possibilities

Per-shard registry files. Editor validation pinned to a release tag of the schema `$id`.

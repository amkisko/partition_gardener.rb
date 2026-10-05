# Checkpoint table name

## Participants

Andrei

## Decisions

SqlRunRecordStore default table is partition_gardener_checkpoints. Hosts set run_record_table_name when they already own another relation. First use with the default name renames partition_gardener_runs or partition_gardener_run_records when that catalog relation exists and the default table does not.

RFC 0011 records the table, the config key, and the rename.

## Effects

lib/partition_gardener/sql_run_record_store.rb and configuration.rb. Docs in configuration, operations, and audit_reference. Specs in sql_run_record_store_spec.rb.

## Next

Hosts that already created partition_gardener_run_records keep resume rows after the first enabled run, or set run_record_table_name to keep the old name.

## Source

RFC 0011

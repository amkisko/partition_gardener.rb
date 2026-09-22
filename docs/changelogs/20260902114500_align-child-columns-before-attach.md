# Align child columns before attach

## Participants

Andrei

## Decisions

ATTACH PARTITION now runs additive column align first (default on). CREATE TABLE LIKE and DETACH snapshot columns; a later parent ADD COLUMN does not reach that child. Align adds all missing ordinary columns in one ALTER TABLE statement (skip identity and generated), preserving type, non-default collation, default, and NOT NULL. PostgreSQL rejects the complete statement when existing rows cannot satisfy NOT NULL, so standalone execution does not leave a partial alignment. Extra child columns stay. Existing types and other constraints are not rewritten.

Audit warns when an unattached managed child still lags the parent. Built-in strategies filter unrelated prefixed tables and load all candidate column metadata in one catalog query. Custom partition name formatters retain prefix discovery because detached tables have no parent provenance. align_child_columns: false keeps fail-fast attach. JSON registry import rejects non-boolean align_child_columns values.

## Effects

LIKE and keep-table reattach paths attach after a parent ADD COLUMN without a host workaround. A missing conflict-key column is aligned before its child index is created.

## Source

https://github.com/amkisko/partition_gardener.rb/issues/18

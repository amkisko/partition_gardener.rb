# Align child columns before attach

## Participants

Andrei

## Decisions

ATTACH PARTITION now runs additive column align first (default on). CREATE TABLE LIKE and DETACH snapshot columns; a later parent ADD COLUMN does not reach that child. Align adds missing ordinary columns (skip identity and generated), copies type and default, and SET NOT NULL only when the child is empty or the column has a default. Extra child columns stay. Types and constraints are not rewritten.

Audit warns when an unattached child still lags the parent. align_child_columns: false keeps fail-fast attach.

## Effects

LIKE and keep-table reattach paths attach after a parent ADD COLUMN without a host workaround.

## Source

https://github.com/amkisko/partition_gardener.rb/issues/18

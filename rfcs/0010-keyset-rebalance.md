# RFC 0010: Keyset rebalance

- Feature Name: keyset-rebalance
- Type: Standards Track
- Status: Stable
- Created: 2026-09-09
- Author: Andrei Makarov
- Stakeholders: project maintainers
- Relates: RFC 0003, RFC 0005
- Requires: RFC 0004

## Summary

Specify batched row moves: insert into the destination with `ON CONFLICT DO NOTHING`, then delete source rows that landed or already exist at dest. Staging name and drain order are part of the contract.

## Motivation

Moving millions of rows in one statement locks the parent too long. Retry after a crash must not duplicate conflict_key values or leave rows only in staging.

## Guide-level explanation

A reshape of `_future` copies rows into `{table}_rebalance_staging` in batches of 10000, then into the destination child. Each batch inserts first. Rows whose `conflict_key` already exists at dest are treated as moved and deleted from the source. Default drain runs last so a hole never lasts across the rest of the run.

## Reference-level explanation

Cursor columns come from the registered config. Default `move_batch_size` is 10000. Staging child name is `{table}_rebalance_staging` (RFC 0006).

SQL order per batch: `INSERT INTO dest SELECT … FROM source WHERE cursor > last ORDER BY cursor LIMIT n ON CONFLICT (conflict_key) DO NOTHING`, then `DELETE FROM source` for keys that exist in dest (including keys the insert skipped). Do not delete from source before the insert.

`UnmovedRowsRemaining` is a run error when a batch cannot make progress.

The host application MUST supply a partition key on insert. PostgreSQL routing errors and overflow into `{table}_default` stay a host contract; gardener drains default last (`DateRangeMaintenance#run!`).

`incremental_rebalance` may stop after a budget of batches and resume via run records (RFC 0011).

### Fail modes

Empty `conflict_key` is a registry error (RFC 0004). A unique violation that is not on `conflict_key` is a run error. Staging MUST NOT remain attached after a successful reshape of that source.

## Implementation notes

`Executor#execute_move_batch`. Drain last: `DateRangeMaintenance#run!`.

## Registrar

`conflict_key`, `move_batch_size`, `incremental_rebalance`. Error `UnmovedRowsRemaining`. Staging suffix `_rebalance_staging`.

## Drawbacks

Insert-then-delete is slower than a single `INSERT … SELECT` with no conflict. Hosts that document delete-then-insert in application notes would disagree with this SQL.

## Rationale and alternatives

Insert first keeps dest complete if the process dies mid-delete. Rejected: delete-then-insert, which can lose a row if insert fails. Rejected: `ON CONFLICT DO UPDATE`, which would overwrite dest.

## Prior art

Keyset pagination. PostgreSQL `ON CONFLICT DO NOTHING`.

## Unresolved questions

Whether hash remainder moves share this batch size default without a separate RFC.

## Future possibilities

Parallel batches per source child. A progress metric other than `rows_moved`.

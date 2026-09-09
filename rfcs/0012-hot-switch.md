# RFC 0012: Hot switch

- Feature Name: hot-switch
- Type: Standards Track
- Status: Stable
- Created: 2026-09-09
- Author: Andrei Makarov
- Stakeholders: project maintainers
- Relates: RFC 0006, RFC 0010

## Summary

Specify `PartitionGardener::Migration::HotSwitchConcern`: a shadow parent, delta copy, and rename swap so an unpartitioned table becomes partitioned with a short exclusive lock.

## Motivation

`CREATE TABLE … PARTITION BY` on a large live table is not available as a non-blocking rewrite. Hosts need a numbered rename protocol so plan and audit after the switch still match RFC 0006 names.

## Guide-level explanation

A Rails migration includes the concern, builds `p_events` with the same columns, copies rows, optionally blocks writes, then renames `events` to `events_old` and `p_events` to `events`. Child names lose the `p_` prefix. Sequences follow the live name. Later `plan events` uses `events_2026_09`, not `p_events_2026_09`.

## Reference-level explanation

Shadow prefix is `p_`. Swap: live → `{table}_old`, shadow → live. Attached children rename to drop the shadow prefix. Sequences owned by the live table retarget.

Helpers: `ensure_future_partitions_exist`, `sync_delta_data`. Optional write-block around the rename. `swap_lock_timeout` default `5s`.

Plan and audit MUST use post-switch names (RFC 0006). Occupancy (RFC 0002) applies to the live parent after rename.

The host MUST stop writers or accept a window where inserts hit `_old`. Gardener does not fence application connections.

### Fail modes

Timeout on swap is a migration failure; leave `{table}_old` and the shadow for operator recovery. Do not half-rename children. Column align (RFC 0013) on the shadow MUST finish before swap.

## Implementation notes

`lib/partition_gardener/migration/hot_switch_concern.rb`.

## Registrar

Module `PartitionGardener::Migration::HotSwitchConcern`. Prefix `p_`. Suffix `_old`. `swap_lock_timeout`.

## Drawbacks

Two full-size tables exist until `_old` drops. A 5s lock can still stall a busy writer.

## Rationale and alternatives

Rename is shorter than copying back. Rejected: logical replication as the only path. Rejected: keeping `p_` on live children after swap.

## Prior art

pgslice `swap`. Rails `disable_ddl_transaction!` plus exclusive lock.

## Unresolved questions

Whether gardener should drop `{table}_old` after a successful audit, or leave that to the host.

## Future possibilities

A write-block adapter for a specific job queue. Online copy via logical decoding.

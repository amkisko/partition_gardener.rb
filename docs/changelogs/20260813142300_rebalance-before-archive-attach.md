# Rebalance before archive attach

## Participants

Andrei

## Decisions

Date-range maintenance rebalances the sliding-window tail before it finalizes monthly archives or applies retention. That lets one run detach a current partition that still starts on 1 July, attach a new current partition from 1 August, send July rows to default, and attach a non-overlapping monthly child from default.

Archive attach is skipped when the bucket start is at or after the attached current partition lower bound. Those buckets wait until rebalance moves the current span forward. The lower bound is read with Connection.current_partition_lower_bound.

## Effects

A July-to-August maintenance sequence attaches the July monthly child and a current partition from 1 August.

## Source

Requested in the partition_gardener sliding-window rollover fix. Specs: spec/integration/sliding_window_maintenance_spec.rb and spec/partition_gardener/attach_retry_spec.rb.

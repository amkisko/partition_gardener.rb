# Specify shipped contracts as Stable RFCs

## Participants

Andrei

## Decisions

Write Standards Track Stable RFCs for every shipped contract named in the RFC gap analysis, including layouts and execution paths that were previously operator-guide only. Skip whether-to-partition advice, engine recipes, monitoring SLOs, host CI, job wiring, and landscape UI notes. Skip registry ensure flags. Occupancy for integer catalogs stays an unresolved question, not a claimed walk.

RFC numbers: 0003 sliding-window-layout, 0004 registry-json, 0005 plan-audit-reports, 0006 archive-naming, 0007 retention, 0008 cli, 0009 maintenance-backends, 0010 keyset-rebalance, 0011 advisory-lock-run-records, 0012 hot-switch, 0013 child-column-align, 0014 integer-window, 0015 hash-list-composite.

Facts preserved: current is origin filler, not this month. Default is always created except hash. Apply always needs --confirm. Moves are insert then delete with ON CONFLICT. partition_key_column is trusted operator SQL.

## Effects

The RFC files and id claims exist on this branch. Indexes and Related links point at the set.

## Next

Review Proposed RFC 0002. Follow-on RFC if integer occupancy ships. Do not bump the gem version for documentation-only RFCs.

## Source

Requested after RFC 0001 and RFC 0002. Related usr/docs/changelogs/20260909164000_shipped-contract-rfcs.md.

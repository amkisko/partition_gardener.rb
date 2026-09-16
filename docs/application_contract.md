# Application contract

How host applications should behave around partitioned tables: queries, writes, public identifiers, maintenance side effects, bulk load, and replicas. For UI scoping and aggregate snapshots see [partition_landscape.md](partition_landscape.md). For operator runbooks see [operations.md](operations.md).

## Query and write basics

- Hot-path reads and writes include the partition key in plain predicates (no wrappers on the key column).
- `conflict_key` columns match the parent unique index; updates and deletes use `query_constraints` when the logical id is not globally unique ([partition_landscape.md](partition_landscape.md#rails-application-contract)).
- Inserts supply a routable partition key value so rows land in named children, not only in `default`.
- When only a logical id or parent reference is available, follow the recovery ladder in [partition_landscape.md](partition_landscape.md#routing-hints-when-the-key-is-not-in-hand).
- Public URLs and API ids follow [Public identifiers](#public-identifiers).
- After maintenance with high `rows_moved`, refresh `id → partition_key` mappings when the partition key can change.

## During maintenance (row moves)

Maintenance runs move rows in batches keyed by `(partition_key, conflict_key)`:

- Moves are delete-from-source, insert-into-target within transactions; logical row identity is preserved when `conflict_key` is stable.
- Row-level triggers and callbacks fire per batch; prefer idempotent side effects or defer heavy work to jobs keyed by `conflict_key`.
- Counter caches and Rails `counter_cache` on associations may drift during moves; use snapshots or reconcile after maintenance ([partition_landscape.md](partition_landscape.md#aggregates-totals-and-snapshots)).
- Outbox and change-data-capture streams may emit move pairs; consumers should treat `(id, partition_key)` as identity.

After a run with high `rows_moved`, schedule snapshot recompute for affected buckets and watch replica lag.

## Insert routing failures

Row in `default` — key outside attached bounds or horizon lag. Application response: fix key; gardener drains default on next run.

PostgreSQL routing error — no child accepts key. Application response: `apply` to extend horizon; never silence without ops review.

Duplicate key across children — overlapping manual DDL. Application response: stop writes; `plan` / `apply`; remove overlapping attach.

Applications should not catch routing errors and retry without the partition key.

## Public identifiers

Treat database uniqueness, public identifier, routing hint, and authorization as four contracts. PostgreSQL uniqueness on a partitioned parent is composite because the partition key must sit in every unique index. That does not by itself decide what a person sees in a URL or API.

When a single sequence or UUIDv7 keeps `id` unique across children, keep that logical id as the application identifier: `self.primary_key = :id` so `to_param` and JSON stay a scalar, not a Rails underscore composite such as `42_100`. Still attach a routing hint on point lookups so `SELECT` can prune. Do not invent that hint from current month.

When `id` is unique only inside a child, the public identifier for point lookups must carry every uniqueness column. Prefer one opaque path segment over Rails `extract_value` underscore form (`4_2`) or a separate query parameter the caller can edit independently.

Prefer Rails APIs over a homemade encoding:

- True composite `primary_key` (array): `signed_id` / `find_signed` or `to_sgid` / `SignedGlobalID`. Both uniqueness columns travel; `find` can prune. `signed_id` uses HMAC SHA256, JSON, and `url_safe: true`. The payload is encoded, not encrypted.
- Scalar `primary_key = :id` plus `query_constraints`: `signed_id` and `generates_token_for` still sign and find by `id` alone. `query_constraints` never feeds `SELECT`. Sign `[id, partition_key]` with a host `ActiveSupport::MessageVerifier` (`url_safe: true`), or resolve through an unpartitioned mapping table.
- `has_secure_token` stores a random Base58 mapping value. A unique index on that column alone is illegal on a partitioned parent unless the partition key is in the index. Put the mapping off the partitioned fact table, or keep a globally unique logical id on the fact row.
- Default `MessageVerifier` is not URL-safe. `signed_id` and `GlobalID::Verifier` opt into `url_safe`. Do not encrypt identifiers with `MessageEncryptor`.
- Unsigned GlobalID (`gid://app/Event/123/2026-03-15`) and `to_param` underscore composites are tunable. Keep them off public point-lookup URLs.
- Extra JSON in `generates_token_for` is compared after fetch. It is not a `WHERE` predicate and is plaintext in the token.

Active Record 7.1 is this gem's development floor. Composite `find_by_token_for` needs 7.2 or 8.0. Composite `find_signed` wrapping `primary_key => [id]` needs 8.1. Hosts on 7.1 should verify finders before relying on signed composite lookup.

After decode, query with both columns and fail closed. Do not fall back to id-only scan. A bad or unsigned token is 404, not a bounded retry across children. Encoding is packaging, not authorization. Lookups still go through an ownership set.

List screens still show period, account, or branch in product language ([partition_landscape.md](partition_landscape.md#ui-and-product-surfaces)). Tenant and list keys for hot paths come from session or parent context, not from a tunable URL field. Pagination cursors already belong in the same family as opaque tokens.

Gardener does not ship an encoder. Host applications own secrets, token version, and decode.

## Bulk import and backfill

- Chunk `COPY` or `insert_all` by bucket window within partition bounds (month, week, day).
- Set partition key explicitly on every row; do not rely on defaults that omit the key.
- Run imports during low traffic or against a shadow table during cutover ([cutover.md](cutover.md)).
- Disable or throttle per-row callbacks on mass load; run bucket snapshot recompute after import completes.

## Read replicas

- Row moves generate write load on the primary; replicas may lag during large `rows_moved` nights.
- Do not run reporting aggregates on replicas that must be strictly current during maintenance windows; use snapshots or primary with bounded windows.
- Logical replication of partitioned parents replicates to the parent; child layout is visible on subscribers. Coordinate major layout changes with replication monitoring.

## Foreign keys and references

PostgreSQL limits foreign keys referencing partitioned tables and FKs across partition boundaries. Prefer:

- Application-level integrity for cross-table references into partitioned facts.
- Composite references that include the partition key when FKs are required.
- Document any FK from partitioned child to dimension table in migration reviews.

Gardener does not add or remove FKs during maintenance.

## Sharded applications

Shard plus partition filters on hot paths; see [Rails horizontal sharding](partition_landscape.md#rails-horizontal-sharding). Per-shard maintenance: [operations.md](operations.md#sharded-registries).

```ruby
ApplicationRecord.connected_to(shard: :tenant_a) do
  Event.in_window(month_range).where(workspace_id: workspace.id)
end
```

Registry JSON may differ per shard only if layouts differ (unusual).

## Admin and operator surfaces

- Default filters: current month or selected tenant, not all history.
- Global id search is an advanced, slow path; require date or tenant hint, or resolve through a mapping table before scanning children ([Public identifiers](#public-identifiers)).
- Export flows chunk by bucket; show progress per period.
- Totals read from snapshot tables with `computed_at`, not live `SUM` across all children or a stale materialized view over the full fact table ([partition_landscape.md](partition_landscape.md#materialized-views)).

## Testing expectations

See [host_testing.md](host_testing.md) for CI registry fixtures and integration smoke tests.

## Related

- [partition_landscape.md](partition_landscape.md) — pruning, routing layers and hints, UI, snapshots; `query_constraints` versus `SELECT`
- [cutover.md](cutover.md) — backfill and switch
- [naming.md](naming.md) — child table names

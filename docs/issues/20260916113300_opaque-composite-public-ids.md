# Opaque composite public identifiers

## Participants

Andrei

## Decisions

Treat database uniqueness, public identifier, routing hint, and authorization as four separate contracts. PostgreSQL uniqueness on a partitioned parent is composite because the partition key must sit in every unique index. That does not by itself decide what a person sees in a URL or API.

When a single sequence or UUIDv7 keeps id unique across children, keep that logical id as the application identifier. Use self.primary_key = :id so to_param and JSON do not become Rails underscore composites such as 42_100. Still attach a routing hint on point lookups so SELECT can prune. Do not invent that hint from current month.

When id is unique only inside a child, the public identifier for point lookups must carry every uniqueness column. Prefer one opaque path segment over Rails extract_value underscore form or a separate query parameter the caller can edit independently.

If that segment is encoded, use unpadded base64url from RFC 4648 section 5, not standard base64. Standard base64 uses plus, slash, and padding equals, which are not URL-safe in a path. Encoding is packaging. Anyone can decode and re-encode another date or tenant. Tamper resistance needs an HMAC over a versioned payload, or a server-side mapping table. Encoding is not authorization. Lookups still go through an ownership set.

After decode, query with both columns and fail closed. Do not fall back to id-only scan. A bad or unsigned token is 404, not a bounded retry across children.

Do not hide browse context. List screens still show period, account, or branch in product language. Tenant and list keys for hot paths come from session or parent context, not from a tunable URL field. Point-lookup tokens may be opaque. Pagination cursors already belong in the same family as opaque tokens.

Do not ship an encoder in this gem until a second in-repo caller needs it. Host applications own secrets, token version, and decode. Gardener docs should name the contract.

Rails already covers the packaging the first pass sketched. Prefer those APIs over a homemade base64 string.

signed_id (Rails 7+) is an HMAC token over record.id, SHA256, JSON, url_safe: true. The docs say the payload is encoded not encrypted. find_signed fails closed on a bad signature. That is the closest out-of-box match to one opaque URL-safe path segment. It only carries both uniqueness columns when primary_key is the composite array. Scalar self.primary_key = :id plus query_constraints still signs and finds by id alone, so SELECT can scan every child. query_constraints never feeds SELECT.

to_param plus params.extract_value is the Rails CPK URL form. Default delimiter is underscore (4_2). Callers can edit either half. Dates and other values that contain underscore split wrong unless param_delimiter is changed. Use this for private admin paths, not for a public identifier that must not be tunable.

generates_token_for can embed extra JSON (password salt, or occurred_on) and re-check it after fetch. Lookup still yields only the primary key into find_by or find. Extra JSON is not a WHERE predicate and is plaintext in the token. CPK find_by_token_for was fixed in 2024 (Rails 7.2/8.0). find_signed CPK wrap landed later (Rails 8.1 / 2026-04). Gardener's development floor is ActiveRecord 7.1, so hosts on 7.1 cannot treat signed CPK find as solved.

has_secure_token stores a random Base58 string (URL-safe by alphabet). It is a mapping column, not an encoding of composite values. PostgreSQL still forbids a unique index on token alone on a partitioned parent unless the partition key is in that index. Lookup by token without the partition key then cannot prune, or the unique index cannot exist. Put the mapping on an unpartitioned table, or keep a globally unique logical id on the fact row.

GlobalID locates with Model.find(model_id). Composite keys become gid://app/Event/123/2026-03-15 (slash, CGI.escape, max 20 segments). Unsigned. to_param is unpadded base64url of that URI, still decodable. SignedGlobalID HMAC-wraps the same URI. Locator find prunes only when primary_key is the composite.

ActiveSupport::MessageVerifier is the primitive under signed_id, token_for, and SignedGlobalID. Default MessageVerifier is not URL-safe (plus, slash, padding). signed_id and GlobalID::Verifier opt into url_safe. MessageEncryptor exists; do not encrypt identifiers. CurrentAttributes can hold session tenant for list filters; that is not a public id.

## Effects

Added Public identifiers to docs/application_contract.md. Pointers from docs/partition_landscape.md Rails application contract, routing hints, and UI surfaces. README application_contract blurb names public identifiers. CHANGELOG Unreleased and usr/docs/changelogs/20260916144600_public-identifiers-contract.md record the doc contract.

## Next

Host docs only. No encoder in the gem. No RFC unless a later change makes public identifiers a user-facing gem contract.

## Source

Triggered by a review question: should composite ids for users be a single base64 string of composite values so callers cannot easily tune them and so the value stays URL-safe.

Later pass accepted the proposal as host documentation. Vendor product names stay out of the host contract; they remain a Source citation only.

Existing repo text: docs/partition_landscape.md Opaque tokens may encode (id, partition_key); Rails query_constraints; UI and product surfaces require visible period or tenant for browse. docs/application_contract.md query_constraints when logical id is not globally unique.

Materialized in docs/application_contract.md Public identifiers, docs/partition_landscape.md pointers, README application_contract blurb.

External: GitLab Database table partitioning, Rails Composite Primary Keys guide to_param 4_2 and extract_value, ActiveRecord::SignedId (url_safe MessageVerifier, find_by primary_key => [id] on main), ActiveRecord::TokenFor payload_for [id, block.as_json], has_secure_token SecureRandom.base58, URI::GID COMPOSITE_MODEL_ID_DELIMITER slash, GlobalID to_param unpadded base64url, Rails PRs 52798 and 57245, RFC 4648 section 5 base64url, GraphQL Relay global object identification, OWASP Insecure Direct Object Reference Prevention Cheat Sheet.

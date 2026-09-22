# Public identifiers contract

## Participants

Andrei

## Decisions

Host applications treat database uniqueness, public identifier, routing hint, and authorization as four contracts. When id is unique across children, keep a scalar application id and attach a routing hint on point lookups. When id is unique only inside a child, the public point-lookup identifier carries every uniqueness column as one opaque path segment.

Prefer Rails signed_id or SignedGlobalID when primary_key is the composite array. When primary_key stays :id, sign [id, partition_key] with a host MessageVerifier or use an unpartitioned mapping table. query_constraints still only helps writes. Do not use to_param underscore form or unsigned GlobalID for public point lookups. Fail closed after decode. Browse screens still show period or tenant. Gardener does not ship an encoder.

## Effects

docs/application_contract.md gained a Public identifiers section. docs/partition_landscape.md Rails application contract, routing hints, and UI surfaces point to it. README application_contract blurb names public identifiers.

## Next

No RFC unless public identifiers become a gem runtime contract.

## Source

usr/docs/issues/20260916113300_opaque-composite-public-ids.md

# RFC 0001: RFC process

- Feature Name: rfc-process
- Type: Procedural
- Status: Proposed
- Created: 2026-09-09
- Author: Andrei Makarov
- Stakeholders: project maintainers
- Feedback until: 2026-09-23

## Summary

This RFC defines how Partition Gardener design changes are proposed, written, numbered, and advanced. Files live flat under `rfcs/NNNN-slug.md`. Shared shape comes from `amkisko/rfc-process`.

## Motivation

Layout names, registry JSON, audit warnings, and child slot names are the public contract. usr/docs traces record work. Numbered RFCs are the unit for a change that would move those contracts.

## Guide-level explanation

Claim `ids/NNNN` with one line: the kebab slug, or `reserved` then the slug. Copy `0000-template.md`, delete the optional-header instruction, fill the sections that apply, omit unused header fields and empty sections, and open `rfc: NNNN short title`. Two pull requests that add the same `ids/NNNN` path conflict in git. Discussion is the pull request. Stakeholders are maintainers plus owners of the touched area. The default clock is two weeks of lazy consensus.

After merge, implementation PRs cite the RFC number.

An RFC proposes a design. Version numbers belong in changelogs. Shipped behavior is already accepted, so an RFC that specifies already-shipped design is Stable on merge. Experimental means the design is not yet the product contract. Proposed means a change is under review.

Trivial exemption: a bugfix that restores documented behavior, a typo, or a refactor that does not change bytes a user can observe.

## Reference-level explanation

### Citations

Isolation is off. RFCs MAY name repository paths a reviewer can open. Prefer another RFC for design cross-references.

### Header

Required: Type, Status, Created, Author. The title is the H1.

Optional, omit unused: Feature Name, Stakeholders, Feedback until, Relates, Requires, Supersedes. Describes is historical; new RFCs omit it.

### Shape

Required sections: Summary, Motivation, Guide-level explanation, Unresolved questions. Summary is one paragraph: the suggestion. Product RFCs also fill Reference-level explanation, Drawbacks, Rationale and alternatives, and Prior art. Implementation notes are optional. Omit unused sections.

### Length

Prefer under 150 lines. Split a second RFC when a file grows past that because it has two concerns.

### Vocabulary

Name the contract with instrument and protocol words: check-in, last-seen, probe, monitor, expected tick. Body and organism metaphors stay out of titles, registrar names, paths, CLI verbs, and identifiers.

### Number assignment

The author claims a number by adding `ids/NNNN`. After a conflict, the later change takes a free id and updates the draft filename. Existing numbers stay. 0001 is this process document.

## Drawbacks

Authors pay process overhead. The trivial exemption and Stable status for already-shipped design keep that cost down.

## Rationale and alternatives

usr/docs traces record decisions. RFCs are the public, numbered discussion unit. Vision bands are unused here; numbering is sequential from 0001.

## Prior art

Rust RFC template; Mozilla Android RFC stakeholders and feedback window; XEP-0001 types and Experimental to Final; polyrun RFC 0001; kiskolabs/pray RFC 0001.

## Unresolved questions

Whether this repo will add an automated id checker, or keep git add/add conflicts as the only reservation signal.

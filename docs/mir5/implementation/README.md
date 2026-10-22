---
title: "Implementation draft: reading order and boundaries"
status: draft
applies_to: "MIR replacement development; explanatory pseudocode, not executable product"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-implementation-draft-README
---

# Implementation draft 01

**Purpose:** turn the supplied proposed specification into reviewable control flow, ownership rules and opposing tests. This is not an implementation, an API stability declaration, or a new normative specification.

## Read only the relevant part

| File | Use |
|---|---|
| [Blueprint](blueprint.md) | Pseudocode from settings declaration to prototype publication, API use, runtime and migration. |
| [Review](review.md) | What is already specified, what remains unresolved, and narrowly proposed refinements. |
| [Opposing tests](opposing-tests.md) | Independent expected properties and examples of defects the tests must detect. |

The authority remains [the specification index](../../../spec/mir5/README.md). The reviewed baseline is `MIR5_REPO_SPEC_DOCS_DIAGRAMS_2026-10-22.zip`, with the exact digest in the accompanying delivery manifest. API signatures follow its **1.0.0-draft.2**, not earlier messages in the discussion.

## What the notation means

- Uppercase procedures are explanatory operations, **not new public API functions or mandatory modules**.
- `REQUIRED_RECOVERY(...)` denotes a concrete missing historical value or rule. It is a stop condition, never a shipped fallback, placeholder technology, guessed default or runtime data loader.
- `PROPOSAL` denotes a refinement to review before amending the indicated specification. This draft cannot silently change that contract.
- `OWNED` means one component may mutate the table; `BORROWED` means it must not. These are documentation conventions, not a runtime ownership framework.
- Assertions are intended behavior. No pseudocode assertion is an executed test.

The blueprint uses ordinary native-shaped Lua records. It does not introduce a serialized instruction language, plugin scheduler, generic mutation plan, second technology catalogue or compiler intermediate representation.

## Boundaries that remain fixed

Keep authored research identities and progression; permit exact bindings, finite alternatives and specifically justified bounded recipe collection. Keep full applicable delivered settings, continuations, overrides, runtime, Library and integration behavior. Do not defer them by calling the replacement a smaller core. Runtime and migrations never import the Generator. External data calls execute immediately. Historical identity preservation is decided before an omission branch.

## What is deliberately not supplied

There are no Factorio source files, native test results, recovered production technology IDs, invented cost curves, speculative migration values or new numerical performance results in this addendum. The baseline's continuity groups remain unreconciled and its native acceptance remains not run.

## Import and cutover

The addendum introduces four files in `docs/mir5/implementation/`. It updates only the baseline pack's `tools/mir5/adoption/pack_members.json` so that the existing exact-membership checker can recognize them. No existing specification, source, API example, root document, test oracle or acceptance status is replaced.

Review that one manifest change against the baseline before overlaying it; do not overwrite a locally modified membership manifest. On a modified checkout, reconcile the additional four paths rather than blindly applying the supplied manifest.

These implementation drafts are temporary explanatory material. During final cutover, keep only sections that remain useful to contributors; retire duplicated draft rationale. Do not preserve this folder as a competing permanent architecture authority.

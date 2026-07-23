---
title: "TechnologyDesign Schema"
status: current
applies_to: "3.2.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---

# TechnologyDesign Schema

`TechnologyDesign` schema 2 is the normalized design boundary shared by fixed streams, automatic streams, and base-chain continuations. `prototypes/mir/domain/technology/technology_design.lua` is the machine authority for dimensions, typed subjects, materialization kinds, maturity enums, evidence classes, lock states, lock policies, required leaf paths, cross-field invariants, canonical projections, and fingerprints.

The required design dimensions are `identity`, `effects`, `progression`, `cost`, `presentation`, `ownership`, and `runtime_contracts`. Every dimension and leaf provenance record declares `present`, `value`, `source`, `evidence_class`, `lock_state`, `locked`, and `lock_policy`. `locked` remains a compatibility boolean and is true only when `lock_state` is `all`; the authoritative states are `none`, `partial`, and `all`.

`materialization.kind` is `create`, `patch-existing`, `continuation`, or `diagnose`. It is part of design identity. The common emitter accepts only `create` and `continuation`; patch operations require a transaction that verifies their input and output fingerprints.

Materialization, maturity, validation-evidence, identity, runtime-action, and public-claim values are closed enums. Cross-field validation is fail-closed: `diagnose` designs cannot declare an emitting runtime action, creating designs cannot claim an existing owner, patch designs must bind their transaction target and input/output identities, and an emitted or adopted design cannot remain proposal-only. Validation writes diagnostics to the design being validated; it never repairs or mutates the caller's context object.

Leaf records remain authoritative. A dimension is `partial` when only some leaves are locked, such as a released technology ID with an adaptive candidate ID or reviewed localized text with fallback-derived icons. `adaptive-within-envelope` fields require a machine-readable envelope. `TechnologyDesign.diff`, `TechnologyDesign.assert_locks`, and `TechnologyDesign.merge` enforce locked paths and adaptive envelopes during policy composition.

## Typed subjects

The semantic subject model contains `recipes`, `products`, `items`, `fluids`, `entities`, `technologies`, `effect_targets`, `science_packs`, and `surfaces`. Direct-effect subjects preserve their actual modifier type and target instead of collapsing every direct-effect stream into one capability. `members` remains a compatibility projection of the recipe, item, fluid, and entity subject sets and must match them exactly.

## Independent identities

Schema-2 records carry four distinct identities:

| Fingerprint | Material |
| --- | --- |
| `subject_fingerprint` | Semantic capability, family, partition, and typed subjects. |
| `design_fingerprint` | Identity, effects, progression, cost, presentation, ownership, and runtime design values. |
| `prototype_fingerprint` | Canonical normalized Factorio technology projection. |
| `qualification_fingerprint` | Subject, design, and prototype identities plus exact context, gates, provenance, maturity, locks, and evidence. |

`semantic_fingerprint` remains a compatibility alias for `qualification_fingerprint`; it is not a pure design identity.

The canonical projections are `graph_projection`, `prototype_projection`, `presentation_projection`, and `save_identity_projection`. Output parity compares the full prototype projection, including localized name, localized description, single-icon or layered-icon fields, order, level, declared enabled and hidden state, and upgrade behavior.

## Identity authority and maturity

Identity stability is not inferred from a non-empty proposed technology name. It is one of `unassigned`, `provisional`, `reserved`, `stable-unreleased`, `released`, or `retired`, and it must match `identity_authority.state`. Existing fixed streams use their legacy stream-manifest authority. The two predeclared 3.1 automatic-family identities explicitly declare `identity_state = released`; a future procedural candidate defaults to `provisional` until a promotion authority says otherwise.

The design-maturity state machine is `proposed` to `experimental` to `automation-qualified` to `human-reviewed` to `promoted` to `released-canonical`. Validation evidence is independently `none`, `fixture`, `exact-mod`, `exact-ecosystem`, `upgrade-qualified`, or `interactive-qualified`. Passing a safety gate never promotes identity, validation, design, applicability, runtime action, or a public claim.

## Hard-gate lifecycle

Every hard gate is an explicit record with one of `not-applicable`, `pending`, `passed`, `failed`, or `superseded`. A `pending` gate yields a proposal, not a false pass or terminal rejection. `passed` and `failed` gates are authoritative only when they bind an evaluator identity, sorted evidence, and the canonical evidence fingerprint. `superseded` preserves the prior and replacement identities so provisional planner evidence cannot be confused with final graph or output evidence.

`SafetyQualification` is the hard-gate aggregate. `DesignAssessment` evaluates quality independently. `PromotionAuthorization` records separately governed trust and evidence. None can be inferred from another.

## GenerationPlan boundary

Every schema-3 `emit` or `adopt` row must carry one validated schema-2 `TechnologyDesign`. The compatibility `fields` record is checked against the IR and cannot disagree with it. Compilation planning, stream emission, adoption transactions, and output validation consume canonical projections from the IR.

Every accepted base continuation is likewise rebuilt as a `continuation` design after sanitation and cross-operation policy. Its generated identity derives from the released chain pattern in the continuation manifest, and the same TechnologyDesign adapter that emits streams creates the final prototype.

A native-owner adoption row uses `materialization.kind = patch-existing`. Its target and operation must match the adoption plan, its configured-field list is explicit, and its canonical prototype projection is the complete expected owner snapshot after adoption. The design's context binds both transaction input and output fingerprints. GenerationPlan and CompilationPlan reject any mismatch, the emission-owned adoption transaction rechecks the projection and both fingerprints before touching the prototype, and output validation consumes the same design. Patch designs are compiler artifacts; they are not published into the generated-technology registry or runtime adoption namespace.

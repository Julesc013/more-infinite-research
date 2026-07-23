---
title: "CompatibilityPack Schema"
status: current
applies_to: "3.1.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-24
supersedes: []
superseded_by: []
---

# CompatibilityPack Schema

A schema-2 `CompatibilityPack` is a data-only refinement packet. It cannot contain functions, prototype mutation callbacks, emitters, or direct technology definitions.

Every pack declares:

- a stable ID and `mods_any`, optional `mods_all`, and optional `mods_none` applicability groups with comma-separated semantic version comparisons; the legacy `mods` field remains the `mods_any` spelling;
- aliases, exact includes and excludes, family or tier hints, and science roles;
- exact owner claims, reviewed risk overrides, explicit family-generation authorizations, and exact candidate seeds;
- positive Factorio target lines;
- fixture and real-mod evidence;
- a claim level and explicit public or internal boundary.

An `allow-reviewed` risk override is limited to a named reviewable signal, an exact recipe selector, an exact applicable mod version, and evidence IDs already declared by the pack, including a dedicated positive fixture. Hard facts such as effective productivity denial, zero caps, parameterization, recycling, self-return, nondeterministic products, catalysts, productivity exclusions, and blocking infinite owners are never overridable. Fixture-only packs cannot publish a claim.

External fixtures may register a pack through the internal `more-infinite-research-compatibility-pack` `mod-data` prototype. MIR validates the complete packet during final planning and fingerprints the active pack set into `GenerationPlan`. This is not a stable public extension API.

Active fields are production inputs: exact excludes and includes participate in deterministic precedence, aliases and family hints refine candidates, science roles include or exclude declared packs for a stream, and owner claims feed the owner policy. Candidate seeds union an exact reviewed recipe into an existing FamilyRule and stable stream, but the candidate must still pass every hard gate. Equal-precedence conflicting actions fail closed.

When a candidate seed supplies `item`, it is the one exact candidate item and is not ambiguous. When `item` is omitted, MIR infers it only from exactly one deterministic item result; zero or multiple candidates remain `REVIEW_REQUIRED`.

`exact-pack` mode starts with the safe attachment baseline and emits only a generic family named by an active `action = generate` authorization. Each authorization binds pack ID, exact applicability, family or stream, fixture evidence, and claim boundary. An unrelated active pack cannot enable either generic family.

Compatibility packs never create technologies and cannot bypass target, effect identity, owner, science, lab, prerequisite, loop-safety, whole-plan, or emission validation. Test-only packs are injected by fixtures and never added to the production profile registry.

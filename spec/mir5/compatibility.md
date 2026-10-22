---
title: "Compatibility and binding"
status: proposed
applies_to: "MIR replacement development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-compatibility-specification
---

# Compatibility and binding

`COMP-01` — Compatibility supplies explicit variants, exact target bindings and meaningful field checks. The Generator does not know ecosystem names. Adding an adapter must not introduce a whole-modpack fingerprint or another inference engine.

## Three binding paths

1. **Exact:** named recipe, owner, prerequisites and science vector. Prefer this when it preserves the existing effect coverage.
2. **Finite alternatives:** a short authored list selected by relevant current fields. No transitive production-route search or guessed progression.
3. **Bounded collection:** a retained broad contract may collect matching recipes for an already-authored research family in one relevant pass. Build a typed-product → interested-family map, then visit product entries once and emit only approved matches. Work is proportional to visited input plus actual matches/output, not families multiplied by all recipes.

`COMP-02` — A collector may select targets; it must not invent technology identities, science, prerequisites or family meaning. It lives outside the Generator. A public API call does not trigger global collection. Repeated calls cannot silently initiate repeated world passes. Scope any reusable result to the data-stage phase in which its inputs are valid; later foreign prototype edits invalidate that assumption. Prefer one explicit integration point over a generic invalidation system.

Do not silently shrink old product-based targeting to one vanilla recipe. Conversely, a shared output name does not prove arbitrary recycler/catalyst economics safe. Preserve relevant quantity, type, probability, ignored-productivity and excluded-return semantics. Where an obligation cannot be expressed safely in the allowed mechanisms, record the exact conflict and withhold the affected completeness claim.

## Activation and load order

Check only relevant active mods/settings before importing an integration body. Production admission and exact test locks differ: a tested tuple is evidence; a blanket tuple fingerprint is not automatically the best applicability rule. Relax a restriction only after identifying the fields it protects. Do not claim all future patches work because a recipe name exists.

For Bob/Angel combined behavior, use one explicit combined rule where needed. Do not assume independently correct integrations compose automatically. Define priority and affected IDs, not last-writer-wins order. No arbitrary `priority` system that resolves every unknown pair.

Data stages and dependencies are part of each adapter's contract. If a consumer requires MIR prototypes before its updates, do not move them all into MIR final-fixes. Later third-party finalizers may still change them; state the qualified load-order boundary. [Factorio lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html)

## Outcome classes

| Situation | Required action |
|---|---|
| Optional upstream mod absent | Do not import adapter; ordinary non-applicability |
| New optional contribution explicitly disabled | Apply its documented disable policy |
| Supported native owner already supplies effect | Retain owner or perform the exact authored extension; no duplicate bonus |
| Known variant differs | Select an approved alternative, or report unsupported input |
| Existing saved identity would disappear | Apply a qualified preservation/migration rule or block that upgrade; not a silent skip |
| Duplicate owner/name or malformed required definition | Programming/conflict error, caught before release; no swallowed failure |
| Unknown mod changes unowned content | Leave it alone; no fabricated support claim |

## Science and graph constraints

Use authored Base/Space Age progression, with relevant adapter checks for modded vectors. Preserve non-tool research items where the target supports them. A recipe existing is not proof that it is usable or that its progression is correct. A union of multiple labs' inputs is not proof that one lab accepts the vector.

Broad science/lab policies retain their actual settings semantics. No new full-factory acquisition solver. Keep known source types explicit: recipe, named resource, and supported rocket-trigger/payload/output relationships. The cryogenic regression suite must distinguish missing/zero/wrong typed outputs, disabled triggers, independently seeded alternatives and self-supporting cycles.

Author MIR-to-MIR prerequisites in a declared acyclic order. Adding nodes pointing into an acyclic prior graph does not create a cycle only if no external path points back into the new nodes. Do not claim that condition for arbitrary foreign finalizers. A feature that deliberately edits old prerequisites may require a single scoped linear check; review it explicitly rather than reintroducing repeated graph planning.

## Support evidence

`COMP-03` — Record a dependency-valid engine/mod/settings/profile and separate declared, loaded, researchable, effect-observed, physically productive, migrated, reloaded, multiplayer-tested and measured states. AAI, Bob, Angel, BZ, Py, K2, SE, K2SE and IR are ecosystem names, not interchangeable test environments. K2SO and K2SE are different integrations. Existing delivered scope is retained; undeveloped coverage remains the existing backlog.

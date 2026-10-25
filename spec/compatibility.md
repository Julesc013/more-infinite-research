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
2. **Finite alternatives:** a short, flat authored list selected by relevant current fields. Reject nested alternatives; do not interpret recursive acquisition trees. No transitive production-route search or guessed progression.
3. **Bounded collection:** a retained broad contract may collect matching recipes for an already-authored research family in one relevant pass. Build a typed-product → interested-family map, then visit product entries once and emit only approved matches. Work is proportional to visited input plus actual matches/output, not families multiplied by all recipes.

The recovered prerequisite repairs are independent named F200/F210 bindings, not a foreign-technology planner. With active Angel Smelting, an enabled `modules` technology may drop only its disabled `angels-silver-smelting-1` prerequisite. With both Astroponics and Planet Muluna active and the declared `astroponics` → `space-science-pack` edge present, the sole recovered cycle binding performs one iterative proof over only prerequisite edges reachable from `space-science-pack`; if that finite reached subgraph returns to `astroponics`, it removes only the declared first edge. Each reached technology and edge is visited at most once, so the proof is O(reached V + reached E); it neither enumerates the prototype world nor performs recursive planning, researchability checks or factory acquisition. Other mods and non-reachable prerequisites remain untouched, and future behavior outside these named inputs remains unqualified.

`COMP-02` — A collector may select targets; it must not invent technology identities, science, prerequisites or family meaning. It lives outside the Generator. A public API call does not trigger global collection. Repeated calls cannot silently initiate repeated world passes. Scope any reusable result to the data-stage phase in which its inputs are valid; later foreign prototype edits invalidate that assumption. Prefer one explicit integration point over a generic invalidation system.

The retained science-pack productivity family includes every current lab input that resolves to a concrete ItemPrototype, independently of the research-ingredient policy. When that authored family is selected and not explicitly replaced by an exact profile binding, collect and locally sort/deduplicate those input names once, then add one typed-item rule at the family's normal weight to the existing recipe pass. Preserve static-rule precedence, disabled producer eligibility and the collector's yield/type/productivity-denial/recycling safeguards. This selects producer effects without examining foreign research owners or inventing progression; an absent or exact-bound family does not inspect labs.

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

For `all`, an unfamiliar lab input may use one context-scoped direct-source collection outside the Generator. Support an initially enabled positive item recipe, or a no-prerequisite owner with an independent craft-item trigger or finite research unit using already-authored direct seeds in one accepting lab. Validate every difficulty form, retain item/fluid distinctions, and attach only the selected owner for a newly appended pack. Existing ingredients do not gain inferred gates; explicit source contracts never fall through to discovery. Default/official-only selection and `all` without a missing unbound input perform no such collection. This restores the direct class witnessed by the published 4.7.3 synthetic fixture; it does not prove factory acquisition or traverse transitive foreign research. Other unbound cases retain their actual unresolved disposition and are not completeness claims.

Author MIR-to-MIR prerequisites in a declared acyclic order. Adding nodes pointing into an acyclic prior graph does not create a cycle only if no external path points back into the new nodes. Do not claim that condition for arbitrary foreign finalizers. A feature that deliberately edits old prerequisites may require a single scoped linear check; review it explicitly rather than reintroducing repeated graph planning.

## Support evidence

`COMP-03` — Record a dependency-valid engine/mod/settings/profile and separate declared, loaded, researchable, effect-observed, physically productive, migrated, reloaded, multiplayer-tested and measured states. AAI, Bob, Angel, BZ, Py, K2, SE, K2SE and IR are ecosystem names, not interchangeable test environments. K2SO and K2SE are different integrations. Existing delivered scope is retained; undeveloped coverage remains the existing backlog.

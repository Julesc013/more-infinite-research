---
title: "Recipe Productivity Capability"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-10-10
supersedes: []
superseded_by: []
---

# Recipe Productivity Capability

Recipe productivity is the capability lane that creates `change-recipe-productivity` effects for validated recipe families.

`prototypes/mir/index/recipe_facts.lua` scans final recipe prototypes once and keeps the normalized authority private. RecipeFactV2 preserves typed variant ingredients/products, probabilities, catalysts, productivity exclusions, surface conditions, and source class while retaining the aggregate compatibility fields used by existing matchers. `prototypes/mir/index/relationships.lua` derives shared lookups by output, ingredient, category, unlock, placement result, entity type, effect identity, lab pack, module tier, upgrade, subgroup, and surface. Recipe productivity matching, science pack production facts, compatibility diagnostics, and the diagnostic fact registry share those authorities instead of rebuilding independent views. The generation-integrity fixture asserts a single recipe scan and copy isolation. Prototype mutation passes and the recycler pre-mutation safety classifier remain phase-local live-prototype operations, not competing general fact authorities.

Productive item/fluid identities require a positive output roll and useful bonus quantity. Shared probability requires a positive valid interval; modern roll fields follow the selected target contract. An unexcluded fractional item roll can provide useful output with a zero base amount on F210/F200. Fractional returns with excluded base quantities remain conservative pending native evidence. These facts feed the existing typed material and dynamic lab-science selectors. They grant no garden, seed, carrier-return or process-loop exception. `tests/compiler/material_routes.lua` consumes the canonical fact index and matcher under all nine target contracts; controlled replay does not qualify current packages, upstream finalizers or production in a saved world.

Supported results that provably cannot occur do not create material return edges, seed candidate process cones or block useful recipes as carrier returns. This includes zero quantities, zero independent rolls and empty native shared-roll intervals. Bonus exclusions do not remove baseline return edges. Unknown or foreign fields, positive fractional returns and positive coproduct paths retain their possible edges. Pattern-selected recipes with no known productive output are withheld. These checks establish possible process connectivity and useful bonus output, without establishing full stoichiometric loop safety or renewable biology acceptance.

Automatic placeable manufacturing uses the canonical productive identity and requires a finite positive fixed item quantity with useful bonus remaining in every retained variant. The family operator reads productivity exclusions from the shared recipe semantics and target profile; explicit zero overrides the modern `ignored_by_stats` default. `non_productive_placeable_output` is a hard family blocker, so a compatibility attachment cannot override it. Existing single-output, deterministic-output, author-permission, risk and ownership gates remain in force. The registered capability-negative fixture includes zero-quantity and fully excluded native cases; current-package fixture, catalogue and save acceptance remain pending.

The material guard also follows native item spoilage when `spoil_ticks` is positive and `spoil_result` names an item. A possible return to a route ingredient through spoilage remains withheld even when a recipe-only forward-route certificate exists. Relevant spoilage transitions, including their duration and alternate producers of the output, enter the certificate fingerprint; disconnected transitions leave existing recipe-only bindings unchanged. These facts share the existing item index and its compiler context. Controlled regressions cover direct and mixed recipe/spoilage paths, version-independent item/fluid separation, cache reuse and certificate rejection. This does not qualify trigger-created products, planting/mining conversions or native production and save behavior.

## Gates

- Target recipes must exist and be visible unless the stream explicitly opts in.
- Recipe productivity must be allowed by the prototype.
- The recipe must not be owned by a conflicting infinite technology unless an exact replacement or adoption policy passes.
- Science ingredients must be lab-compatible.
- Loop-risk and recovery signals must be rejected or explicitly allowed.
- The generated stream must have a stable manifest row.

## Related Docs

- [Stream manifest schema](../reference/schemas/stream-manifest.md)
- [Generated ID reference](../reference/generated-id-reference.md)
- [Policy overlays](../compatibility/policy-overlays.md)

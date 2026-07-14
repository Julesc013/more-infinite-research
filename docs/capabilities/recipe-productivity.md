---
title: "Recipe Productivity Capability"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# Recipe Productivity Capability

Recipe productivity is the capability lane that creates `change-recipe-productivity` effects for validated recipe families.

`prototypes/mir/index/recipe_facts.lua` scans final recipe prototypes once and keeps the normalized authority private. RecipeFactV2 preserves typed variant ingredients/products, probabilities, catalysts, productivity exclusions, surface conditions, and source class while retaining the aggregate compatibility fields used by existing matchers. `prototypes/mir/index/relationships.lua` derives shared lookups by output, ingredient, category, unlock, placement result, entity type, effect identity, lab pack, module tier, upgrade, subgroup, and surface. Recipe productivity matching, science pack production facts, compatibility diagnostics, and the diagnostic fact registry share those authorities instead of rebuilding independent views. The generation-integrity fixture asserts a single recipe scan and copy isolation. Prototype mutation passes and the recycler pre-mutation safety classifier remain phase-local live-prototype operations, not competing general fact authorities.

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

---
title: "RecipeFactV2 And Relationship Indexes"
status: current
applies_to: "post-3.1 dev"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# RecipeFactV2 And Relationship Indexes

`prototypes/mir/index/recipe_facts.lua` is the single build-once recipe authority. A schema-2 recipe fact preserves:

- default, normal, and expensive variants when present;
- typed ingredients and products;
- fixed or ranged amounts, probability, catalyst amount, and productivity/stat exclusions;
- categories, main product, research enablement, hidden and parameter state;
- productivity and quality policy fields;
- surface conditions and a conservative source class.

The compatibility aggregate fields from schema 1 remain available so existing matchers can migrate without changing behavior.

`prototypes/mir/index/relationships.lua` derives one immutable shared index snapshot from final prototype state. It owns recipe lookups by output, ingredient, category, and unlock; item placement and subgroup links; entity type, subgroup, upgrade, and surface links; technology effect identities and recipe-productivity owners; lab acceptance by science pack; and modules by tier.

Consumers receive deep copies. Index modules may inspect final prototypes but may not mutate them. Policy, capability, and planner code must use these facts instead of creating another general prototype scan.


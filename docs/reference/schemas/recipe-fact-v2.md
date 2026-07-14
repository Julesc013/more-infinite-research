---
title: "RecipeFactV2 And Relationship Indexes"
status: current
applies_to: "3.1.0+"
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
- fixed or ranged amounts, independent and shared probability, extra-count probability, catalyst amount, and productivity/stat exclusions;
- item freshness and quality constraints, including spoilage, reset/fresh flags, quality bounds, quality change, and quality-roll participation;
- categories, main product, research enablement, hidden and parameter state;
- productivity and quality policy fields;
- surface conditions and a conservative source class.

Declared recipe policy fields and their target-aware effective values are both retained. On Factorio 2.1, an omitted `allow_productivity` resolves to `false`, `allow_quality` resolves to `true`, and `maximum_productivity` resolves to `3.0`; normal or expensive definitions inherit an explicit root declaration before the target default is applied. A recipe is productivity-eligible only when every materialized variant is effectively eligible.

The compatibility aggregate fields from schema 1 remain available so existing matchers can migrate without changing behavior. The legacy product field `probability` is retained as declared evidence on older targets, while Factorio 2.1 normalization uses `independent_probability` as the effective probability authority. Structural family generation rejects any non-unit independent probability, shared probability, non-zero `extra_count_fraction`, range, catalyst, or productivity-excluded amount.

`prototypes/mir/index/relationships.lua` derives immutable phase-labelled input and output snapshots. The input snapshot is built after bounded pre-plan mutations and before MIR generation; the output snapshot is built after all plan operations and post-plan mutations. They own recipe lookups by output, ingredient, category, and unlock; item placement and subgroup links; entity type, subgroup, upgrade, and surface links; technology effect identities and recipe-productivity owners; lab acceptance by science pack; and modules by tier.

Consumers receive deep copies. Index modules may inspect final prototypes but may not mutate them. Policy, capability, and planner code must use these facts instead of creating another general prototype scan.

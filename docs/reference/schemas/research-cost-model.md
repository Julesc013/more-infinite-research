---
title: "ResearchCostModel Schema"
status: current
applies_to: "3.2.4+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-03
supersedes: []
superseded_by: []
---

# ResearchCostModel Schema

`ResearchCostModel` schema 1 and formula ABI `mir-research-cost-v1` represent the complete cost curve for one infinite technology:

```text
cost(L) = (base_cost + linear_increment * (L - anchor_level))
          * growth_factor ^ (L - anchor_level)
```

| Field | Contract |
| --- | --- |
| `schema` | Exactly `1` |
| `formula_abi` | Exactly `mir-research-cost-v1` |
| `anchor_level` | Integer at least `1`; the first controlled technology level |
| `base_cost` | Finite value at least `1`; exact cost at the anchor before no offset |
| `linear_increment` | Integer at least `0` |
| `growth_factor` | Finite value at least `1` |
| `derived_kind` | `fixed`, `linear`, `exponential`, or `hybrid`, derived rather than configured |
| `count_formula` | Deterministic canonical Factorio formula |
| `provenance` | Source for every independent parameter and the anchor |
| `fingerprint` | Content identity over schema, ABI, parameters, derived material, and provenance |

The pure validation layer requires positive nondecreasing costs. The bounded classifier accepts arithmetic syntax only, reduces the expression structurally to an affine factor times at most one exponential factor, and never executes external text. Default native-owner adoption preserves the original external formula verbatim. An explicit override rebuilds a recognized model canonically; a formula outside this family rejects the override.

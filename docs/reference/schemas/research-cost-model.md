---
title: "ResearchCostModel Schema"
status: current
applies_to: "3.2.4+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-05
supersedes: []
superseded_by: []
source_of_truth_for:
  - research-cost-model-schema
  - legacy-coefficient-anchor-projection
  - research-cost-algebraic-qualification
  - research-cost-parser-and-numeric-envelope
  - research-cost-3.2.5-release-contract
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

The pure validation layer requires positive nondecreasing costs. Qualification ABI `mir-research-cost-qualification-v1` binds algebraic proof ABI `mir-research-cost-algebraic-proof-v1`: for offset `n >= 0`, `base_cost >= 1`, `linear_increment >= 0`, and `growth_factor >= 1` imply both factors are positive and `cost(n + 1) / cost(n) >= 1`. Qualification therefore checks the governed endpoint for the finite numeric envelope; it does not infer the property from sampled levels.

The governed model envelope is exact:

| Quantity | Bound |
| --- | --- |
| Anchor/research level | integer `1..1,000,000` |
| Base cost | finite `1..2,147,483,647` |
| Linear increment | integer `0..2,147,483,647` |
| Growth factor | finite `1..1,000` |
| Qualification offset/exponent | integer `0..100` |
| Evaluated cost | finite `1..1e300` |

The bounded classifier accepts arithmetic syntax only, reduces the expression structurally to an affine factor times at most one exponential factor, and never executes external text. It rejects formulas over 512 bytes, 128 tokens, parse depth 32, or 96 AST nodes; numeric literals above absolute `1e300`; and constant exponent offsets above absolute `1,000,000`. Rejection is fail-closed and preserves an unchanged external formula unless a user requests an unsafe override, which is refused. Default native-owner adoption therefore preserves the original external formula verbatim. An explicit override rebuilds a recognized model canonically; a formula outside this family rejects the override.

The model stores anchor semantics, not setting-storage semantics. In particular, the stable base-continuation `mir-cost-base-*` setting remains the historical level-one coefficient used by MIR 3.2.3 and earlier. The continuation planner first canonicalizes the coefficient and growth through the historical six-significant-digit formula boundary, then projects that coefficient by `growth_factor ^ (anchor_level - 1)` before placing it in `base_cost`. A neutral linear increment therefore reproduces the old realized curve, while a nonzero increment begins at the first controlled level.

The release-specific machine authority is `.mir/research-cost-contract-3.2.5.json`. It binds the five direct 3.2.3 upgrade archetypes, all sixteen formula-family transitions, first and second upgraded-save reloads, ownership dispositions, and one Factorio 2.0 disposition for every shipped 3.2.5 cost feature. It is a product contract awaiting source freeze; it does not assign a candidate or create 2.5.5 release authority.

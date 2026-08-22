---
title: "ResearchCostModel V2 Preview"
status: draft
applies_to: "MIR 4 developer preview"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-21
supersedes: []
superseded_by: []
---

# ResearchCostModel V2 Preview

ResearchCostModel V2 is a package-excluded experimental contract. The shipped player model remains schema 1 with formula ABI `mir-research-cost-v1`. V2 does not create settings, emit technology prototypes, change runtime progress, or grant a public compatibility claim.

The preview exists to freeze and test the public feature request without partially replacing the stable cost authority. Its schemas are `spec/schemas/experimental/mir4-research-cost-model-v2.schema.json` and `spec/schemas/experimental/mir4-research-cost-profile-rules-v1.schema.json`. The reference implementation is `tools/lib/mir4/ResearchCostV2.ps1`.

## Exact cost contract

For level offset `d = level - anchor_level`, the preview evaluates:

```text
round_half_up(
  (
    prerequisite_anchor * base_multiplier
    + prerequisite_anchor * linear_ratio * d
    + absolute_linear_increment * d
  )
  * growth_factor ^ d
)
```

All five numeric inputs use reduced, non-negative rationals represented by decimal numerator and denominator strings. A rational is reduced before it participates in an identity. The single rounding law is `round-half-up-positive-final-v1`; binary floating-point text is not part of the semantic identity.

The supported base sources are:

| Source | Meaning |
| --- | --- |
| `absolute` | An explicit exact anchor. |
| `previous-series-level` | The realized cost of one named predecessor. |
| `direct-prerequisite-sum` | The deduplicated direct prerequisite costs. |
| `transitive-prerequisite-closure` | Every unique reachable prerequisite cost. |
| `profile-defined` | An exact anchor supplied by the selected profile. |

Graph snapshots are immutable inputs to one resolution. Contributor IDs are sorted, shared prerequisites are counted once, self-reference is forbidden, and generated continuation nodes are not contributors. A reachable cycle blocks derivation with a deterministic path witness. Every accepted derived anchor records the ordered contributor IDs and exact realized costs.

## Sparse profile rules

Rules may select all features, a target, owner, source mod, effect channel, family, stream, or exact technology. They are layered in this order:

```text
safe default
target
ecosystem
modpack
user
explicit
hard safety
```

Within a layer, broad selectors apply before specific selectors; priority and stable rule ID break remaining ties. The resolver returns the effective field values, every applied rule ID, and the final source of each field. Hard safety is always last and cannot be bypassed by user or exact-technology rules.

No startup setting is generated for dynamic technologies. A future admitted product implementation may consume a static profile or bounded extension fragment, but that transport is outside this preview.

## Migration and admission

The preview can calculate the analytical transition fraction once:

```text
new fraction = clamp(old fraction * old realized cost / new realized cost)
```

That calculation is diagnostic only. Factorio normalizes active research during configuration changes, so a stable runtime implementation must prove whether the engine already performed the conversion and must never apply it twice.

Stable admission remains blocked until all of the following pass on the exact candidate:

- formula lowering into each admitted Factorio target;
- direct-predecessor upgrade, first reload, and second reload;
- active research and queued research transitions;
- target-local f210 and f200 proof;
- profile transport, Inspector explanation, and manual review;
- rollback from V2 to V1 without progress or ownership loss.

Until then, every target disposition is preview, preserved, or omitted and the stable V1 cost model remains authoritative.

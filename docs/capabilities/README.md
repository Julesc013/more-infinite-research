---
title: "Capabilities"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# Capabilities

Updated: 2026-07-07

Capabilities are the middle layer between prototype facts and emitted MIR technologies. They answer:

```text
What kind of thing does this prototype set appear to be, and what is MIR allowed
to do with it?
```

They do not automatically mean "generate a technology."

## Contract

A capability resolver follows this contract:

```lua
CapabilityResolver = {
  id = "loader-manufacturing-productivity",
  schema_version = 2,

  discover = function(facts) end,
  classify = function(candidate, facts) end,
  propose = function(classified, facts, policy) end,
  validate = function(proposal, facts, policy) end,
  materialize = function(validated, decision_context) end,
  result = function(materialized, report_context) end,
}
```

The current resolver contract is report-first. It materializes typed decisions but cannot emit prototypes. Prototype creation requires a validated `GenerationPlan` and `StreamSpec` with a stable manifest row, owner checks, lab checks, cap diagnostics, loop-risk denial, fixture evidence, and claim text.

## Capability Lanes

| Capability | Purpose | Default 3.0 posture |
| --- | --- | --- |
| `recipe-productivity` | Generate recipe productivity effects for exact or policy-approved recipes. | Safe generate only with full gates. |
| `machine-manufacturing-productivity` | Classify recipes that craft machines. | Report first, then safe generate by family. |
| `logistics-manufacturing-productivity` | Classify recipes that craft belts, loaders, and logistics items. | Existing stream ownership first. |
| `loader-manufacturing-productivity` | Detect loader recipes structurally from placeable loader entities. | Existing belt stream or report-only. |
| `mining-drill-manufacturing-productivity` | Detect mining drill recipes structurally from placeable drill entities. | Existing drill stream or report-only. |
| `native-mining-yield` | Observe or govern mining yield technologies. | Observe/prefer existing. |
| `native-belt-stack` | Observe or govern belt stack size technologies. | Observe/prefer existing. |
| `native-lab-productivity` | Observe or govern lab productivity technologies. | Prefer base/external unless explicit. |
| `native-lab-speed` | Observe lab speed technologies. | Observe by default. |
| `science-pack-integration` | Decide whether added science packs join MIR science productivity and generated research costs. | Safe when lab-compatible. |
| `lab-compatibility` | Prove generated technologies are researchable by at least one lab. | Hard gate. |
| `ore-processing` | Classify ore crushing, sorting, washing, and similar families. | Report first, then narrow streams. |
| `tile-surface` | Classify landfill, foundation, asphalt, concrete, and surface/tile recipes. | Diagnostic until balance policy exists. |
| `loop-risk` | Detect self-return, recovery, catalyst, voiding, recycling, and transmutation loops. | Diagnostic-only by default. |
| `owner-conflict` | Detect external finite/infinite owners for the same effects. | Preserve unless exact policy passes. |
| `rule-surface-observer` | Observe mods that mutate caps, modules, beacons, recyclers, labs, or allowed effects. | Diagnostic-only. |
| `migration` | Preserve released generated technology IDs. | Required for renames/removals. |

## Productivity Is Not One Mechanism

Keep these separate:

| Request | Lane | Technology effect or model |
| --- | --- | --- |
| Craft more filters, loaders, drills, or machines | Recipe productivity | `change-recipe-productivity` |
| Mining drills produce more ore | Native mining yield | `mining-drill-productivity-bonus` |
| Belts/loaders carry stacked items | Native logistics | `belt-stack-size-bonus` |
| Labs produce more research | Native lab productivity | `laboratory-productivity` |
| Labs research faster | Native lab speed | `laboratory-speed` |
| More robot range/speed/battery | Native robot modifiers | worker robot modifiers |
| Added science packs work | Science/lab integration | technology ingredients and lab inputs |

This split prevents loader crafting productivity from being confused with loader throughput, and mining-drill crafting productivity from being confused with mining-yield productivity.

## Evidence And Confidence

Name matching is weak evidence. Structural prototype relationships are stronger.

For a loader manufacturing candidate, good evidence includes:

- item exists;
- item has `place_result`;
- placed entity type is `loader` or `loader-1x1`;
- a visible recipe produces the item;
- unlock technologies can be derived;
- an existing MIR stream or exact policy owns the effect.

For a mining-drill manufacturing candidate, good evidence includes:

- item exists;
- item has `place_result`;
- placed entity type is `mining-drill`;
- placed entity exposes drill properties such as mining speed and resource categories;
- a visible recipe produces the item;
- unlock technologies can be derived.

Confidence should be decomposed:

```lua
confidence = {
  identity = 0.98,
  family = 0.92,
  unlock = 0.87,
  science = 1.00,
  lab = 1.00,
  owner = 1.00,
  loop_safety = 0.95,
  cap = 0.90,
  total = 0.93,
}
```

A strong name match must not hide weak science, owner, or loop evidence.

## Settings Posture

Do not add vague global settings such as "generate productivity for modded machines." Prefer capability settings only when there is implemented behavior to control:

```text
Loader manufacturing productivity:
  off / safe / propose-only

Mining drill manufacturing productivity:
  off / safe / propose-only

Native mining yield productivity:
  observe / prefer-existing / MIR-explicit

Native belt stack/logistics:
  observe / prefer-existing / MIR-explicit
```

Per-mod marketing settings are not part of the MIR settings model.

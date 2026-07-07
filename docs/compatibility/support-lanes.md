---
title: "MIR Compatibility Program"
status: current
applies_to: "3.0.0+"
audience: modpack-author
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# MIR Compatibility Program

This document defines how More Infinite Research turns external mod signals into
supported behavior. It is deliberately stricter than a feature backlog: a mod can
be useful evidence without becoming MIR-owned behavior.

The goal is not to absorb every productivity-related mod. The goal is to decide
what role MIR should take for each mod, prove that role with fixtures or load
evidence, and keep public claims narrower than the evidence.

## Role Taxonomy

Every audited mod or profile should receive exactly one primary MIR role.

| Role | Decision enum | Meaning |
| --- | --- | --- |
| Replace exactly | `MIR_REPLACE_EXACT` | MIR can safely replace the same infinite technology effect, target, and value. |
| Integrate as MIR-owned stream | `MIR_STREAM_CANDIDATE` | The idea fits MIR, but MIR needs its own designed stream and fixtures. |
| Cooperate, skip, or prefer external | `MIR_COMPAT_ADAPTER` | The external mod owns a native modifier, progression rule, or distinct mechanic that MIR should avoid duplicating. |
| Diagnose only | `MIR_DIAGNOSTIC_ONLY` | MIR should report caps, conflicts, duplicate owners, or wasted infinite levels without changing behavior. |
| Companion territory | `MIR_COMPANION_SCOPE` | The idea is useful but changes factory rules, modules, beacons, machines, or runtime behavior outside MIR core. |
| Docs/load-test only | `MIR_DOCS_ONLY` | The mod is compatible or relevant to test, but not a MIR feature. |
| Reject from core | `MIR_REJECT_CORE` | The mechanic is runtime-heavy, scope-breaking, or unsafe unless a separate design proves otherwise. |

The role question is:

```text
What role should MIR take for this mod?
```

It is not:

```text
Can MIR replace this mod?
```

## Replacement Versus Cooperation

Replacement and cooperation are different products.

Replacement is only valid when MIR proves equivalent or intentionally designed
behavior. The current `2.1.5` known-competitor cleanup is the model:

- the external technology is active and infinite;
- every effect is `change-recipe-productivity`;
- every recipe is covered by enabled MIR replacement effects;
- every `change` value matches;
- replacement science is lab-compatible;
- no blocking external owner remains.

Cooperation is different. For example, `Research_Productivity` creates an
infinite `laboratory-productivity-4` owner. MIR does not replace that mod. MIR
skips its own lab-productivity stream when that exact technology has the expected
native `laboratory-productivity` effect.

Public wording must preserve this distinction:

```text
MIR provides a maintained replacement for the recipe-productivity portion of X.
MIR cooperates with X and avoids duplicate infinite productivity where exact overlap is detected.
MIR does not replace X's beacon, module, runtime, cap, or rule-mutation behavior.
```

Avoid saying "fully replaces X" unless MIR covers every relevant behavior:
settings, startup behavior, runtime scripts, migrations, research costs, unlocks,
dependencies, edge cases, and save behavior.

## Outdated Does Not Mean Replaceable

A Factorio `2.0`-only mod can be outdated for several different reasons. The
MIR response depends on the behavior, not on the age of the mod.

| External behavior | MIR implication |
| --- | --- |
| Simple infinite recipe-productivity techs | Candidate for exact replacement or modern MIR stream. |
| Allowed-effect or machine-rule mutation | Companion scope or docs/load-test only. |
| Productivity cap mutation | Diagnostics or explicit policy, not silent replacement. |
| Runtime stat/entity/productivity systems | Usually reject from MIR core unless bounded and event-driven. |
| Research-cost tools | Cooperation, docs, or load testing; not MIR stream ownership. |
| Abandoned useful concept | Reimplement from first principles after policy and fixture proof. |

## Licensing Rule

Use external mods as behavior evidence, not as source code to copy.

Default rule:

```text
Read behavior.
Record prototype, effect, output, setting, dependency, and runtime facts.
Reimplement MIR-native behavior from first principles.
Cite or credit inspiration where appropriate.
Do not copy code unless the license is reviewed and the attribution obligations are accepted.
```

This rule applies equally to abandoned, outdated, and Factorio `2.0`-only mods.

## Save-Compatibility Questions

Any replacement, skip, or cleanup policy must answer these questions before it is
claimed as supported:

| Question | Why it matters |
| --- | --- |
| What if the external technology was already researched? | Force bonuses, unlocks, and history may already exist. |
| What if another mod depends on that technology name? | Removing or hiding technologies can break prerequisites. |
| What if the player disables the old mod and enables MIR? | MIR cannot always infer old progression or previous settings. |
| What if both mods stay enabled? | MIR needs cleanup, skip, warning, or coexist behavior. |
| What if the external mod has startup settings? | Exact replacement may stop being exact. |

For `2.1.5`, exact cleanup is safe because it is narrow and guarded. The
diagnostics-only planner rows added in the same line do not change save behavior.
For `2.2.0+`, save behavior should be a required row in every compatibility
campaign.

## Test Matrix Model

An all-mods folder load is useful as a non-blocking smoke test, but it is not the
main validation strategy. Many idea mods intentionally conflict in concept.

Use this order:

```text
MIR + one mod
MIR + one family
MIR + known conflict pair
MIR + representative overhaul stack
MIR + full chaos folder as non-blocking smoke test
```

Failures from a full folder load should be triaged as evidence. They should not
automatically block a release unless they identify a MIR regression or a public
claim that is no longer true.

## One-Archive Audit Template

Each archive in `C:\Projects\Factorio\ideamods_mix` should eventually have a
structured row with these fields:

| Field | Purpose |
| --- | --- |
| Mod | Mod Portal name or local archive name. |
| Version | Exact archive version audited. |
| Factorio target | Declared Factorio line. |
| License | License string or license file summary. |
| Dependencies | Required, optional, hidden, incompatible, and recommended dependencies. |
| Data stage touched | Prototype files or data-stage behavior touched. |
| Runtime script | Whether `control.lua` or runtime events exist. |
| Startup settings | Settings that change generated behavior. |
| Technologies added | Technology names and whether they are finite or infinite. |
| Effects added | Effect types, targets, values, and max-level shape. |
| Recipes touched | Recipes added, changed, hidden, or made productivity-eligible. |
| Native modifiers touched | Native technology modifiers besides recipe productivity. |
| Caps touched | `maximum_productivity` changes or cap-like behavior. |
| Allowed effects or machine rules touched | Beacon/module/productivity-rule mutation evidence. |
| Can MIR exactly replace? | Yes only after exact target/effect/value proof. |
| Can MIR provide a designed alternative? | Yes when the concept fits MIR but not as a clone. |
| Should MIR cooperate? | Yes when the external owner should be skipped, preferred, or warned about. |
| Should MIR warn? | Diagnostics needed for caps, duplicate owners, or rule mutations. |
| Should this be companion scope? | Yes for factory-rule mutation or broad runtime systems. |
| Fixture needed | Exact fixture or load scenario required before support. |
| Validation status | Untested, static-only, fixture-proven, targeted load, save-tested. |
| Release target | `2.1.5`, `2.2.0`, future campaign, companion, docs-only, rejected. |
| Notes | Rationale and public wording constraints. |

## Current Lane Model

### Lane A: Exact Replacement Or Cleanup

Examples:

```text
bioflux-productivity
fish-productivity
Science_packs_productivity
ProductivityResearch
ProductivityResearchForEveryone
ProductivityResearchForEveryoneFG
ExpandedProductivityResearch
crafting-efficiency-2
Research_Productivity
```

This lane must remain strict:

```text
same target
same effect type
same value
same infinite ownership
same usable science
no blocking owner
```

### Lane B: MIR-Owned Feature Candidates

Examples:

```text
asphalt-productivity
concrete-productivity
landfill-productivity
foundation-productivity
crushing-industry-productivity-research
py_productivity
selected crafting-efficiency-2 families
selected ExpandedProductivityResearch families
5dim_mining, selectively
```

These should become MIR-designed features, not cloned external behavior.

### Lane C: Diagnostics Or Policy

Examples:

```text
finite_prod_techs
productivity-technology-limit
remove-productivity-cap
modified-productivity-cap
miner-start
mining-prod-0
ResearchProductivity_Rebalance
solar-productivity
```

These mostly feed cap-aware diagnostics, native-overlap policy, or compatibility
warnings.

### Lane D: Companion Territory

Examples:

```text
base-prod
prodforce
Productivity
productivity_fix
Productivity-config
Prod-Beacon
rosnok-productivity-quality-beacon
SchallModules
UnlimitedProductivityFork
space-exploration-spaceproductivity-2
```

These change allowed effects, recipes, machines, modules, beacons, or overhaul
rules. They should not be MIR core unless a companion design deliberately adopts
that product boundary.

### Lane E: Runtime Systems

Examples:

```text
progressive-productivity
productivity-through-science
solar-productivity
```

These are interesting but require runtime state or entity/stat behavior. They
are rejected from MIR core by default unless a bounded event-driven design proves
performance and save behavior.

### Lane F: Utilities, Cost Tools, And UI

Examples:

```text
combatresearchtech
research-control-tower
research-cost-curve
research-fixer
research-multipliers
research-skip
show-missing-bottles-for-current-research
productivity-indicator
productivity_weight_fix
zz-long-science
productivity-module-3-aquilo
more-productivity-research
```

These should usually be tested and documented, not absorbed.

## Modular Architecture Direction

The compatibility architecture should grow in six layers.

### 1. Stream Definitions

Streams describe what MIR owns. They own generated effects, not external mod
behavior.

Example shape:

```lua
{
  id = "ore_crushing_productivity",
  category = "recipe-productivity",
  default_change = 0.10,
  recipes = {
    mode = "exact-visible",
    ids = {
      "iron-ore-crushing",
      "copper-ore-crushing",
      "coal-crushing",
      "calcite-crushing",
      "stone-crushing",
    },
  },
  science = {
    policy = "derive-from-visible-recipes",
    require_lab_compatible = true,
  },
  replacement = {
    mode = "exact-effect-only",
    allow_external_cleanup = true,
  },
  caps = {
    inspect_maximum_productivity = true,
    warn_if_wasted = true,
  },
}
```

### 2. Recipe Resolvers

Recipe discovery should be explicit and reusable:

- exact recipe IDs;
- prototype predicates;
- mod-family resolvers;
- tile and surface resolvers;
- overhaul-family resolvers.

Default to exact IDs for compatibility work. Broad name matching should be rare
and heavily guarded.

### 3. Competitor Profiles

Competitor profiles identify possible external owners. They do not decide
removal.

Example shape:

```lua
{
  mod = "ExpandedProductivityResearch",
  technology_patterns = {
    "^epr_(.+)-productivity%-%d+$",
  },
  role = "candidate-competitor",
  cleanup = "exact-effect-only",
}
```

The cleanup module still proves replacement safety.

### 4. Native Modifier Overlap Policy

Recipe productivity and native modifiers need separate policies.

| Policy | Meaning |
| --- | --- |
| `prefer-base-game` | MIR does not generate if vanilla or Space Age owns it. |
| `prefer-external` | MIR skips when a known external owner exists. |
| `coexist` | Multiple owners are allowed. |
| `warn` | MIR generates but logs duplicate native modifier ownership. |
| `off` | MIR never touches this native modifier. |

Examples of native modifiers that may need policy:

```text
laboratory-productivity
mining-productivity
worker-robot-speed
character-logistic-slots
inserter-stack-size-bonus
```

### 5. Diagnostics Engine

Diagnostics should turn messy mod interactions into visible facts.

Example output:

```text
[MIR] Stream copper-cable-productivity enabled: 1 recipe, +0.10 per level.
[MIR] External competitor epr_copper-cable-productivity-4 found: exact match; cleanup eligible.
[MIR] Recipe landfill has maximum_productivity 300%; MIR infinite stream may stop being useful after N levels.
[MIR] External mod Productivity-config changed allowed effects; MIR is not responsible for that rule change.
[MIR] Skipping research_lab_productivity because laboratory-productivity-4 owns laboratory-productivity.
```

### 6. Validation Fixtures

Every integration should have a fixture or load scenario.

| Fixture type | Purpose |
| --- | --- |
| Exact duplicate owner | Cleanup removes only exact effect/value matches. |
| Wrong value owner | MIR does not silently rebalance. |
| Mixed-effect owner | MIR does not delete mixed-purpose technologies. |
| Missing recipe owner | Uncovered recipes block cleanup. |
| Cap changed | Diagnostics detect useful max-level limits. |
| Native duplicate owner | Skip, warn, prefer, or coexist behavior is proved. |
| Runtime or rule mutator loaded | MIR stays compatible without absorbing it. |

## Compatibility Planner Output

`2.1.5` starts the compatibility planner as diagnostics-only audit rows. `2.2.0`
extends that into a report-only compiler spine that can emit a structured
summary when diagnostics are enabled:

```text
MIR Compatibility Planner

Detected:
- ExpandedProductivityResearch
- Research_Productivity
- finite_prod_techs

Actions:
- Known competitor profile active for epr_* technologies.
- Skipping research_lab_productivity because laboratory-productivity-4 owns laboratory-productivity.
- Recipe caps detected; 12 MIR streams may become ineffective after finite levels.

Non-actions:
- Not changing productivity caps.
- Not changing allowed productivity effects.
- Not changing beacons or modules.
```

The `2.2.0` compiler rows are typed around recipe, technology, machine, lab,
owner, and rule-surface facts. They also emit decision rows, lab-matrix rows,
loop-risk rows, rule-surface rows, owner summaries, and useful cap estimates.
These rows are evidence for future policy gates; they are not broad automatic
support claims.

The procedural compatibility kernel is documented in
`docs/architecture/procedural-compatibility-kernel.md`. Its first capability resolvers are
report-first:

- `logistics-loader-manufacturing` classifies loader crafting recipes from item,
  placed entity, and recipe-output evidence, then reports whether the existing
  belt productivity stream emitted them.
- `mining-drill-manufacturing` classifies drill crafting recipes from item,
  placed entity, and recipe-output evidence, then reports whether the existing
  mining-drill productivity stream emitted them.
- `native-modifier-ownership` reports owners for selected native modifiers,
  including lab productivity, mining yield, logistics stack size, and robot
  bonuses, without stacking or replacing them broadly.

The resolver contract is `discover -> classify -> propose -> validate -> emit
-> diagnose`. In the current implementation, "emit" means "observe the stream or
policy that already emitted". A future resolver can create new technologies only
after it has stable stream IDs, fixture coverage, owner checks, lab checks, cap
diagnostics, and loop-risk denials.

The compatibility platform now has committed machine-readable policy surfaces:

- `prototypes/mir/policy/capabilities.lua` for capability-specific policy;
- `prototypes/planner/generated-stream-manifest.json` for stable generated IDs
  and migration policy;
- `fixtures/compat-matrix/claims.json` for public claim text, capability status,
  generated stream references, and backing fixtures;
- `scripts/Test-MIRPolicyLints.ps1` to reject missing schema fields, generated
  streams without manifest rows, current fixture-backed claims without fixtures,
  and broad public wording.

Negative fixtures are mandatory for capability work that introduces a new
automatic target class. The first negative fixture covers self-return, barrel
return, cleaning, voiding, transmutation, hidden recipe, zero-cap, loader-like
non-loader, and drill-like non-drill cases.

The `3.0.0` line promotes this program into the compatibility compiler
architecture documented in
`docs/architecture/compatibility-compiler-charter.md`. The supporting subsystem
docs are `docs/capabilities/README.md`, `docs/compatibility/policy-overlays.md`,
`docs/reference/schemas/decision-record.md`, `docs/reference/schemas/stream-manifest.md`,
`docs/compatibility/claim-levels.md`, `docs/maintainer/testing.md`,
`docs/releases/3.0.0-migration-guide.md`, `docs/maintainer/README.md`, and
`docs/adr/`.

The long-term data-stage shape should be:

```text
discover facts
  -> classify owners
  -> build complete plan
  -> validate plan
  -> mutate prototypes
  -> emit audit rows from the plan
```

## Compatibility Modes

If a startup setting is added later, prefer one broad compatibility mode over
many per-mod settings:

| Mode | Meaning |
| --- | --- |
| `auto-safe` | Exact duplicate cleanup and known native-owner skips are allowed; no balance-changing replacement. |
| `prefer-mir` | MIR may prefer its streams where explicit policy allows it. |
| `prefer-external` | MIR skips more aggressively when known external owners exist. |
| `coexist` | MIR avoids cleanup and allows duplicate owners unless unsafe. |
| `diagnostics-only` | MIR reports interactions but does not perform cleanup or skip behavior beyond hard safety guards. |

The default should be `auto-safe`.

Do not turn compatibility modes into separate product names. MIR should remain
one mod with one settings page. If future settings expose balance-changing
compatibility behavior, use plain feature-family labels and keep the default
conservative. Source-mod names belong in audit rows and compatibility docs, not
as one-off settings.

For prototype mutation features, disabled must mean no mutation and no broad
scan. Prefer the existing pipeline-extent pattern: default unchanged, the pass
exits early, and diagnostics explain what happened only when the user asks for
reports. Runtime settings should be reserved for real runtime logic with
performance, migration, and uninstall proof.

## Audited Zip Reproducibility

For each compatibility campaign, create a checksum record such as:

```text
docs/audited-zips-YYYY-MM-DD.json
```

The current July 5, 2026 idea-mod ledger is
`docs/archive/2.x/audited-zips-2026-07-05.json`.

Recommended fields:

```json
{
  "bioflux-productivity_0.1.0.zip": {
    "size": 133525,
    "sha256": "...",
    "audited": "2026-07-05",
    "decision": "MIR_REPLACE_EXACT"
  }
}
```

This prevents future Mod Portal updates from silently changing what the audit
proved.

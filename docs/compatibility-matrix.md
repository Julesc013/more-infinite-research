# MIR Compatibility Matrix

This matrix records compatibility claims and planned compatibility campaigns. It is intentionally stricter than the idea backlog: most idea-mod observations are compatibility signals, not planned MIR features. A mod can be interesting without becoming MIR-owned behavior.

Use `docs/compatibility-program.md` for the role taxonomy, one-archive audit template, licensing rule, save-compatibility questions, compatibility-mode policy, and planner architecture direction. This matrix is the claim ledger; the compatibility program document is the decision framework.

Status vocabulary:

| Status | Meaning |
| --- | --- |
| Supported | MIR has code or docs for the behavior and a validation gate for the claim. |
| Planned | Candidate work, but not a public compatibility claim yet. |
| Future campaign | Dedicated post-`2.2.0` compatibility work, not a casual stream batch. |
| Adjacent | Compatible or useful, but outside MIR core unless a separate design accepts it. |

Role vocabulary:

| Role | Decision enum |
| --- | --- |
| Replace exactly | `MIR_REPLACE_EXACT` |
| Integrate as MIR-owned stream | `MIR_STREAM_CANDIDATE` |
| Cooperate, skip, or prefer external | `MIR_COMPAT_ADAPTER` |
| Diagnose only | `MIR_DIAGNOSTIC_ONLY` |
| Companion territory | `MIR_COMPANION_SCOPE` |
| Docs/load-test only | `MIR_DOCS_ONLY` |
| Reject from core | `MIR_REJECT_CORE` |

## Current And Near-Term Matrix

| Mod/profile | Status | MIR action | Validation | Notes |
| --- | --- | --- | --- | --- |
| Idea-mod exact overlap set | Supported in `2.1.5` after final gate | Guarded known-competitor cleanup | Static, runtime fixture, package rebuild, targeted external load pass | Exact infinite recipe-productivity overlaps only. |
| `Research_Productivity` | Supported in `2.1.5` after final gate | Skip MIR lab productivity when infinite `laboratory-productivity-4` has the expected native effect | Static and runtime fixture | Effect-proven exact technology guard, not a broad native-owner policy. |
| `bioflux-productivity` | Supported in `2.1.5` after final gate | Known competitor profile | Targeted external load pass | Exact `bioflux` recipe and `+0.10` replacement only. |
| `fish-productivity` | Supported in `2.1.5` after final gate | Known competitor profile | Targeted external load pass | Exact `fish-breeding` recipe and `+0.10` replacement only. |
| `Science_packs_productivity` | Supported in `2.1.5` after final gate | Known competitor profile for level-4 infinite owners | Targeted external load pass | Finite levels 1-3 are preserved. |
| `ProductivityResearch*` | Supported in `2.1.5` after final gate | Guarded known competitor patterns | Targeted external load pass | Cleanup only fires for exact covered effects. |
| `ExpandedProductivityResearch` | Supported in `2.1.5` after final gate | Guarded known competitor pattern | Targeted external load pass | Broader generator behavior remains out of scope. |
| `crafting-efficiency-2` | Supported in `2.1.5` after final gate | Guarded known competitor pattern | Targeted external load pass | Broader staged families remain candidates only. |
| Compatibility planner/registry | Supported in `2.2.0` as report-only compiler spine | Typed facts, owner summaries, decision rows, lab matrices, non-actions, and planner summary | Static validation and audit rows | Foundation before broad feature absorption. |
| Cap-aware diagnostics | Supported in `2.2.0` as report-only diagnostics | Warning diagnostics and useful-level estimates for non-default recipe caps | Runtime diagnostics with default, raised, lowered, and extreme recipe caps | No silent cap mutation. |
| Loop-risk and rule-surface diagnostics | Supported in `2.2.0` as report-only diagnostics | Observe recycling, cleaning, voiding, container, transmutation, self-return, cap, beacon, lab, and machine-rule surfaces | Static validation and audit rows | False positives are acceptable; behavior remains diagnostic until policy and fixtures exist. |
| `atan-air-scrubbing` | Supported in `2.2.0` | MIR-owned productivity for exact clean pollution and spore filter recipes only | Static and runtime fixture | Does not touch scrubbing, cleaning, recovery, or environmental-removal recipes. |
| `atan-ash` | Planned for `2.2.0` | Candidate MIR-owned ash-processing productivity slice | Recipe-ID fixture with Ash-style recipes | Next ATAN-family proof slice after Air Scrubbing; likely starts from productivity-allowed ash separation and excludes non-productivity conversions. |
| `atan-nuclear-science` | Planned for `2.2.0` | Candidate science-pack productivity and lab/science compatibility slice | Recipe-ID fixture with Nuclear Science-style science pack and atom forge surfaces | Next ATAN-family proof slice after Ash; do not add productivity to non-productivity atom forge crafting. |
| Crushing Industry ore crushing | Planned for `2.2.0` | New stream candidate or guarded profile | Recipe-ID fixture with Crushing Industry | Follow-up family-stream candidate after the ATAN proof slices. |
| `big-mining-drill` | Planned for `2.2.0` | Existing `research_mining_drill` proof slice | Runtime fixture or targeted load profile | Likely validates MIR's current modded drill recipe matching rather than adding a separate stream. |
| `FluidMustFlow` | Planned for `2.2.0` | Load and pipeline-extent coexistence check | Targeted load profile with MIR pipeline defaults | Large duct content, not a productivity stream. Do not recreate ducts or fluid logistics behavior. |
| `robot_attrition` | Adjacent | Runtime balance coexistence only | Targeted load profile | Bot crash behavior is runtime balance, not MIR research ownership. Do not absorb. |
| `jetpack` | Adjacent | Equipment/content coexistence only | Targeted load profile | Player movement equipment and fuel behavior are outside MIR core. Do not absorb. |
| `equipment-gantry` | Adjacent | Equipment-grid automation coexistence only | Targeted load profile | Gantry item/equipment-grid processing is content/runtime behavior, not MIR research ownership. |
| `aai-containers` | Adjacent | Storage content coexistence only | Targeted load profile | Warehouses and logistic container variants are content; do not create research streams unless exact recipe evidence later warrants it. |
| `aai-loaders` | Adjacent | Loader logistics coexistence only | Targeted load profile | Loader operating modes and compatibility hooks are logistics content, not MIR core behavior. |
| `aai-industry` | Planned for `2.2.0` | Mini-overhaul tuning profile for recipe, science, and machine classification | Runtime fixture or targeted load profile | Bridge target before large suites because it alters early industry, recipes, labs, pumps, and progression without becoming a Bob/Angel/Py campaign. |
| Tile/surface productivity mods | Planned for `2.2.0` | Policy before implementation | Balance fixture proving mismatch preservation and exact-match replacement | Values differ across source mods, so this is not a cleanup-only change. |
| `better-bot-battery2` | Supported in `2.1.5` after final gate | Skip MIR worker robot battery stream when effect-proven `worker-robots-battery-6` is present | Static and runtime fixture proving finite levels survive and MIR duplicate is skipped | MIR already has worker robot battery, but Better Bot Battery uses different finite and infinite values. |
| One overhaul material family | Maybe for `2.2.0` | Narrow recipe-family prototype | Fixture with visible recipe IDs | Pick one family; avoid a generic productivity generator. |
| Native modifier overlap policy | Maybe for `2.2.0` | Skip/warn/prefer/allow policy | Fixture with duplicate native modifier owners and settings | Keep small; do not overgeneralize from lab productivity. |
| Beacon/module/productivity-rule mutators | Adjacent | No MIR core absorption | Compatibility load only unless companion design exists | These change factory rules, not only research ownership. |
| Runtime productivity systems | Adjacent | No MIR core absorption | Performance and save-behavior proof before any proposal | Different runtime model and higher UPS/save risk. |

## Future Campaign Matrix

| Mod/profile | Status | MIR action | Validation | Notes |
| --- | --- | --- | --- | --- |
| Krastorio 2 | Future campaign | Load compatibility, recipe-family fixtures, explicit claim rows | MIR + K2 matrix | First large overhaul campaign after the narrow `2.2.0` proof slices; separate from K2 plus Space Exploration and K2 Spaced Out. |
| AAI suite and combinations | Future campaign | Expand from the `aai-industry` tuning profile into explicit AAI combinations only after profile evidence exists | MIR + selected AAI matrix | Keep separate from standalone `aai-industry`, Space Exploration, and K2 combinations. |
| Bob's Library + Bob's Mining | Future campaign | Focused subset load and drill recipe validation | MIR + Bob's Library + Bob's Mining matrix | Likely first Bob's slice. |
| Bob's Library + Bob's Plates | Future campaign | Focused subset load and material-family recipe validation | MIR + Bob's Library + Bob's Plates matrix | Do not claim full Bob's support from one subset. |
| Bob's Library + Bob's Tech | Future campaign | Science/lab compatibility validation | MIR + Bob's Library + Bob's Tech matrix | Science-pack changes need lab compatibility proof. |
| Selected Bob's suite profile | Future campaign | Explicit profile after subset proof | Suite matrix | Claim only the selected profile, not "Bob's Mods" globally. |
| Omni/Angel/Bob Space Age Compat | Future campaign | Suite-aware load and ownership matrix | MIR + Omni/Angel/Bob Space Age Compat matrix | New `ideamods_mix` signal; treat as suite compatibility, not a single stream feature. |
| Space Exploration | Future campaign | Diagnostics plus guarded recipe families only | Dedicated SE matrix | Start only after the requested proof and coexistence ladder is stable; respect SE productivity restrictions and avoid space-rule mutation. |
| Krastorio 2 + Space Exploration | Future campaign | Combination matrix | MIR + K2 + SE matrix | Do not collapse into the standalone K2 claim. |
| Krastorio 2 Spaced Out / Space Age | Future campaign | Separate Space Age-oriented matrix | MIR + K2SO + Space Age matrix | Separate from classic K2 and K2 + SE. |
| Bob's, Angel's, Pyanodons, or larger suite combinations | Future campaign | Campaign after focused proof profiles and K2/AAI lessons | Explicit suite matrix | Avoid broad suite promises without tested profiles. |

Before a future campaign moves from planned to supported, add:

- the exact mod names and versions tested;
- the Factorio line and binary version used;
- the MIR package version and commit;
- the load result and whether the profile is new-game-only or save-migration-tested;
- validation artifacts or test-result rows;
- the assigned MIR role and decision enum;
- the license summary used for reimplementation or attribution decisions;
- save-compatibility notes for already researched, removed, or co-enabled external technologies;
- the recipes, technologies, or native modifiers MIR owns;
- external streams MIR skipped or deferred to another owner;
- duplicate owners MIR removed or deliberately preserved;
- explicit non-ownership notes for balance-sensitive or rule-mutating behavior.

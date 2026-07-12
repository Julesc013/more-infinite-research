---
title: "Manual Test Plan"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# Manual Test Plan

Updated: 2026-07-04

This document defines named manual saves and scenarios. Runtime fixture validation is necessary, but it does not replace save-level gameplay validation.

## Release Use

Use these scenario names in `docs/releases/2.2.0-validation-record.md` so release evidence is comparable across runs.

For the archived `v2.0.5` pre-manual status, see `docs/archive/2.x/pre-manual-2.0.5-report.md`.

## v2.0.5 Quick Feedback Patch

Required before publishing `v2.0.5`:

| Scenario | Purpose |
| --- | --- |
| `branch-state-preflight` | Run `git status --short --branch`, `git log --oneline --decorate --graph --max-count=8`, and `git branch -vv` before push/tag |
| `package-parity` | Rebuild zip and confirm package validation passes |
| `minimal-package` | Confirm the release zip excludes developer docs, fixtures, scripts, and task ledgers while keeping runtime source, locale, migrations, metadata, README, changelog, license, and thumbnail |
| `normal-mod-folder-load` | Copy the release zip into a normal Factorio mods folder and confirm Factorio can see it |
| `vanilla-locale-icons` | Base game without Space Age; confirm Electric Shooting Speed falls back to discharge defense art/description and flamethrower/electric modifier descriptions are present |
| `space-age-electric-icon` | Space Age enabled; confirm Electric Shooting Speed uses the electric-weapons-damage texture while still showing electric and Tesla speed effects |
| `generated-chain-integrity` | Run fixture validation in base-only and Space Age; confirm every generated chain has exactly one owner/continuation and no Space Age vanilla productivity duplicate |
| `circuit-productivity-ownership` | Base-only: green/red/blue circuit recipes are MIR-owned by their recipe IDs. Space Age: green/red stay MIR-owned and processing unit stays vanilla-owned |
| `quality-module-productivity` | Quality enabled; confirm module productivity includes quality module recipes after hidden Quality load ordering |
| `omega-drill-productivity` | Omega Drill or Omega-style fixture enabled; confirm mining drill productivity includes Omega-style drill recipes |
| `tank-uranium-shell-speed` | Confirm tank cannon fire rate with uranium shells is not lower than vanilla after finite vanilla `weapon-shooting-speed-5/6` research |
| `character-reach-icon` | With Character reach bonus enabled, confirm it uses the character mining speed pickaxe icon, not the exoskeleton equipment icon |
| `merged-inventory-trash-ui` | Confirm Character inventory slots shows both inventory-slot and logistic-trash-slot effects, and no separate Character logistic trash slots research appears |
| `fresh-space-age` | Fresh Space Age save with no other mods except MIR |
| `existing-mir-2.0-save` | Existing MIR save upgraded to the release candidate |
| `spoilage-existing-stacks` | Spoilable items already on belts, in chests, in labs, in rockets/platform inventories, and partially spoiled stacks |
| `spoilage-new-stacks` | New spoilable items created before and after spoilage preservation research |
| `spoilage-reversal-disable` | Research, reverse, disable, and re-enable spoilage preservation |
| `gleba-many-agri-towers` | Large Gleba farm with thousands of tower-owned plants |
| `agri-growth-new-plants` | Newly planted tower crops after agricultural growth speed research |
| `agri-growth-existing-plants` | Existing tower-owned plants during research finish/reversal if rescaling is implemented |
| `multi-force` | Multiple player forces with different research levels |
| `no-space-age` | Base game without Space Age; scripted streams should skip safely |
| `custom-labs-science-packs` | Custom science pack and custom lab inputs |
| `duplicate-cargo-tech` | Maraxis-like duplicate cargo landing pad or unloading technology |
| `popular-overhaul-pack` | Large overhaul pack compatible with the current Factorio line |

Default-off scripted agriculture/spoilage candidates can be included in `v2.0.5` with conservative wording. Default enablement, preset inclusion, or strong public behavior claims require the relevant scenarios above to be recorded. If a scripted scenario fails or produces unclear behavior, defer that specific feature, default, or claim to `v2.1.0` or later.

## v2.1.0 Larger Feature Wave

Automated fixture validation now covers the release-candidate claims for the larger `v2.1.0` features. These scenarios remain the manual save-level follow-up matrix for balance, long-running saves, and stronger public claims:

| Scenario | Purpose |
| --- | --- |
| `settings-checkbox-enablements` | Verify per-technology enable checkboxes control generated streams, base continuations, and scripted runtime effects consistently |
| `shareable-presets-design` | Design and validate any future import/export or shareable preset flow before adding preset UI back to startup settings |
| `agri-existing-plant-rescale` | Verify any existing plant rescale is bounded, deduplicated, and reversible |
| `native-modifier-overlap-policy` | Verify overlapping cargo/logistics/native modifiers follow any future selected skip/warn/prefer/allow policy beyond the current diagnostic-only coverage |
| `high-throughput-pump` | Validate prototype, recipe, power draw, balance, and throughput if promoted |
| `pipeline-extent` | Manual soak the implemented startup prototype multiplier with large and modded fluid networks after fixture validation passes |
| `thruster-fuel-productivity` | Manual verify the implemented thruster fuel productivity streams in a Space Age save after fixture validation passes |
| `thruster-oxidizer-productivity` | Manual verify the implemented thruster oxidizer productivity streams in a Space Age save after fixture validation passes |
| `oil-fluid-productivity` | Manual verify the implemented oil processing, oil cracking, lubricant, sulfuric acid, and acid neutralization productivity split after fixture validation passes |
| `panglia-family-adoption` | Verify Panglia or a Panglia-like planet mod adopts extra rocket fuel and low density structure recipes into vanilla Space Age productivity technologies |
| `plates-n-circuit-replacement` | Verify Plates n Circuit Productivity fully covered competing technologies are removed only after MIR replacement effects exist |
| `extended-compat-manual-scenarios` | Run `Invoke-MIRCompatAudit.ps1 -RunManualScenarios` or `Invoke-MIRExtendedTests.ps1 -Tier ManualScenarios -CollectAll` against the executable curated scenario fixture |
| `extended-compat-top25-base-space-age` | Run the top-25 base and Space Age audit tiers with credentials, parse grouped expected/unexpected failures, and only promote repeatable MIR-owned issues into profile work |
| `extended-compat-strict-gate` | Run `Invoke-MIRExtendedTests.ps1 -Tier Static,Runtime,AuditSmoke -FailFast -FailOnAuditFailures` before treating wrapper pass/fail as a release gate |
| `offline-local-library-2-1-curated` | Run `Invoke-MIRExtendedTests.ps1 -Tier LocalLibraryScenarios -LocalModLibraryDirs C:\Projects\Factorio\testmods_2.1 -Offline -CollectAll` to cover curated local combinations first |
| `offline-local-library-2-1-generated` | Run `Invoke-MIRExtendedTests.ps1 -Tier GeneratedLocalScenarios -LocalModLibraryDirs C:\Projects\Factorio\testmods_2.1 -Offline -CollectAll` to cover generated all-local mega and metadata-cluster stress scenarios |
| `offline-local-library-2-1-individual-roots` | Run `Invoke-MIRExtendedTests.ps1 -Tier LocalModZips -LocalModZipDirs C:\Projects\Factorio\testmods_2.1 -LocalModLibraryDirs C:\Projects\Factorio\testmods_2.1 -Offline -CollectAll` to test each downloaded local zip as a root scenario |
| `offline-local-library-2-1-recovery` | Confirm interrupted local sweeps still leave readable `overnight.log`, checkpointed `load-results.json`, grouped `compat-failures.grouped.json`, and `missing-dependencies.*` outputs |
| `offline-local-library-2-1-official-mod-isolation` | Confirm a local root that is incompatible with Space Age can load with Space Age disabled, while a root that requires Space Age gets the full official bundle enabled |
| `offline-local-library-2-1-blank-log-lines` | Confirm blank Factorio log lines do not abort parsed audit-row conversion |

## v2.1.x Spikes

Use throwaway saves or fixtures. Do not promote to release features until the result is documented.

| Scenario | Purpose |
| --- | --- |
| `thruster-fuel-productivity` | Verify recipe productivity on thruster fuel recipes |
| `thruster-oxidizer-productivity` | Verify recipe productivity on thruster oxidizer recipes |
| `oil-fluid-productivity` | Verify recipe productivity on fluid-only and mixed-output oil recipes |
| `high-throughput-pump` | Validate prototype, recipe, power draw, balance, and throughput |
| `pipeline-extent` | Validate startup prototype mutation and compatibility risk |
| `quality-odds` | Determine whether any clean non-runtime-hack path exists |
| `quality-module-enrichment` | Determine whether quality module effect boosts belong as finite prototype tiers, a startup setting, or a companion add-on |
| `roboport-range` | Determine whether a native modifier exists or a prototype tier is required |

## Legacy Backports

Required on the `legacy` branch with a Factorio `2.0.x` binary:

| Scenario | Purpose |
| --- | --- |
| `legacy-1.9.0-static` | Static validation with `factorio_version = "2.0"` and `base >= 2.0` for the `v2.0.5 -> v1.9.0` port |
| `legacy-1.9.0-no-2.1-cargo` | Confirm 2.1-only cargo modifier strings are absent in `v1.9.0` |
| `legacy-1.9.0-runtime-2.0` | Run `Invoke-MIRValidation.ps1` with a Factorio `2.0.x` binary for `v1.9.0` |
| `legacy-1.9.1-runtime-2.0` | Validate the tested `v2.1.0 -> v1.9.1` legacy port |
| `legacy-1.9.2-runtime-2.0` | Validate the tested `v2.2.0 -> v1.9.2` transition port |
| `target-2.3.0-runtime-2.0` | Validate the first Factorio `2.0` port of the MIR 3 architecture |
| `target-1.9.3-runtime-1.1` | Validate the first Factorio `1.1` compatibility port under the locked mapping |
| `target-1.8.0-runtime-0.18` | Validate the Factorio `0.18` bridge/archive package in a matching `0.18` binary |
| `target-1.8.0-bridge-runtime-1.0` | Validate the exact same `1.8.0` zip in Factorio `1.0` before bridge publication |
| `target-1.8.1-runtime-1.0` | Validate the first maintained Factorio `1.0` compatibility port |
| `target-1.7.0-runtime-0.17` | Validate the reduced Factorio `0.17` port and confirm generated streams never depend on disabled tutorial technologies |
| `target-1.7.0-research-all-0.17` | Run `research_all_technologies()` and confirm the next level of each generated infinite stream is available rather than red |
| `legacy-space-age` | Confirm any optional Space Age subset supported by Factorio `2.0.x` |
| `legacy-generated-tech-ids` | Compare generated technology names against expected legacy snapshot |

Do not validate the legacy port with the Steam-updated Factorio `2.1.x` binary.

For the expanded Factorio `1.1` through `0.6` backport ladder, use
`docs/archive/2.x/legacy-backport-cadence.md` as the release matrix. Each target line
needs its own binary smoke check when a compatible binary is available, and
release notes must identify any target-line validation that could not be run.

# Manual Test Plan

Updated: 2026-07-01

This document defines named manual saves and scenarios. Runtime fixture validation is necessary, but it does not replace save-level gameplay validation.

## Release Use

Use these scenario names in `docs/test-results.md` so release evidence is comparable across runs.

## v2.0.5 Quick Feedback Patch

Required before publishing `v2.0.5`:

| Scenario | Purpose |
| --- | --- |
| `branch-state-preflight` | Run `git status --short --branch`, `git log --oneline --decorate --graph --max-count=8`, and `git branch -vv` before push/tag |
| `package-parity` | Rebuild zip and confirm package validation passes |
| `docs-in-package` | Confirm README, roadmap, TODO, API proof, manual tests, compatibility docs, test results, changelog, locale, and source parity |
| `normal-mod-folder-load` | Copy the release zip into a normal Factorio mods folder and confirm Factorio can see it |
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

Scripted agriculture/spoilage can ship in `v2.0.5` only after the relevant scenarios above are recorded. If a scripted scenario fails or produces unclear behavior, defer that specific feature or behavior to `v2.1.0`.

## v2.1.0 Larger Feature Wave

Required before claiming larger `v2.1.0` features:

| Scenario | Purpose |
| --- | --- |
| `settings-presets` | Verify preset defaults and advanced setting override behavior |
| `agri-existing-plant-rescale` | Verify any existing plant rescale is bounded, deduplicated, and reversible |
| `duplicate-native-modifiers` | Verify overlapping cargo/logistics modifiers are skipped, warned, or explicitly allowed |
| `high-throughput-pump` | Validate prototype, recipe, power draw, balance, and throughput if promoted |
| `pipeline-extent` | Validate startup prototype mutation and compatibility risk if promoted |
| `thruster-fuel-productivity` | Verify recipe productivity on thruster fuel recipes if promoted |
| `thruster-oxidizer-productivity` | Verify recipe productivity on thruster oxidizer recipes if promoted |
| `oil-fluid-productivity` | Verify recipe productivity on fluid-only and mixed-output oil recipes if promoted |

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
| `roboport-range` | Determine whether a native modifier exists or a prototype tier is required |

## Legacy Backports

Required on the `legacy` branch with a Factorio `2.0.x` binary:

| Scenario | Purpose |
| --- | --- |
| `legacy-1.9.0-static` | Static validation with `factorio_version = "2.0"` and `base >= 2.0` for the `v2.1.0 -> v1.9.0` port |
| `legacy-1.9.0-no-2.1-cargo` | Confirm 2.1-only cargo modifier strings are absent in `v1.9.0` |
| `legacy-1.9.0-runtime-2.0` | Run `Invoke-MIRValidation.ps1` with a Factorio `2.0.x` binary for `v1.9.0` |
| `legacy-1.9.5-runtime-2.0` | Repeat the same validation for the `v2.1.5 -> v1.9.5` port |
| `legacy-1.9.9-final` | Validate the final Factorio `2.0` port from the latest tested `2.x.x` snapshot |
| `legacy-space-age` | Confirm any optional Space Age subset supported by Factorio `2.0.x` |
| `legacy-generated-tech-ids` | Compare generated technology names against expected legacy snapshot |

Do not validate the legacy port with the Steam-updated Factorio `2.1.x` binary.

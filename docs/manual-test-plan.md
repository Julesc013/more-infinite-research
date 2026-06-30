# Manual Test Plan

Updated: 2026-07-01

This document defines named manual saves and scenarios. Runtime fixture validation is necessary, but it does not replace save-level gameplay validation.

## Release Use

Use these scenario names in `docs/test-results.md` so release evidence is comparable across runs.

## v2.0.5 Stabilization

Required before a stabilization/package release:

| Scenario | Purpose |
| --- | --- |
| `branch-state-preflight` | Run `git status --short --branch`, `git log --oneline --decorate --graph --max-count=8`, and `git branch -vv` before push/tag |
| `package-parity` | Rebuild zip and confirm package validation passes |
| `docs-in-package` | Confirm README, roadmap, TODO, API proof, manual tests, compatibility docs, test results, changelog, locale, and source parity |
| `normal-mod-folder-load` | Copy the release zip into a normal Factorio mods folder and confirm Factorio can see it |

## v2.1.0 Scripted Runtime

Required before claiming scripted agriculture/spoilage features:

| Scenario | Purpose |
| --- | --- |
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

## v1.9.0 Legacy Backport

Required on the `legacy` branch with a Factorio `2.0.x` binary:

| Scenario | Purpose |
| --- | --- |
| `legacy-static` | Static validation with `factorio_version = "2.0"` and `base >= 2.0` |
| `legacy-no-2.1-cargo` | Confirm 2.1-only cargo modifier strings are absent |
| `legacy-runtime-2.0` | Run `Invoke-MIRValidation.ps1` with a Factorio `2.0.x` binary |
| `legacy-space-age` | Confirm any optional Space Age subset supported by Factorio `2.0.x` |
| `legacy-generated-tech-ids` | Compare generated technology names against expected legacy snapshot |

Do not validate the legacy port with the Steam-updated Factorio `2.1.x` binary.

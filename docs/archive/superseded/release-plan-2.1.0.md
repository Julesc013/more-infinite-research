---
title: "More Infinite Research 2.1.0 Release-Gated Plan"
status: archived
applies_to: "1.x-2.x"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: ["../../releases/README.md"]
---
# More Infinite Research 2.1.0 Release-Gated Plan

This document turns the post-`2.0.5` roadmap into an executable release gate for the next Factorio `2.1` feature wave.

Primary rule:

```text
v2.1.0 = user-facing control + compatibility discipline + proof-gated expansion
```

Do not use `v2.1.0` as a bucket for every good Reddit or Discord idea. Every feature must have a lane, an implementation type, and a validation gate before code work starts.

## Release Theme

Ship the features that make MIR easier to control and safer in modded saves:

- simple per-technology checkbox enablement, with shareable presets deferred until there is an import/export design;
- targeted duplicate-productivity compatibility, with the broad native modifier overlap policy explicitly deferred;
- profile-driven compatibility ownership and a repeatable external audit pipeline;
- stricter icon source policy and fallback resolution;
- scripted spoilage/agriculture checkbox routing while stronger behavior claims wait for manual evidence;
- compatibility matrix updates;
- implemented fluid, thruster, and pipeline expansion gated by validation and manual balance evidence.

## Required Ship Gates

These are the core `v2.1.0` gates. The release should not ship without a clear decision for each one.

| Gate | Required outcome | Release blocker? |
| --- | --- | ---: |
| Checkbox enablement | Per-technology enable checkboxes are the single source of truth for stream generation, base continuations, and scripted runtime effects | Yes |
| Shareable presets | Preset import/export remains deferred until it can be designed without adding per-technology override dropdowns | No |
| Native modifier overlap policy | Broad skip/prefer/warn/allow behavior is explicitly deferred; `v2.1.0` ships exact recipe-owner filtering, vanilla family adoption, and known fully covered recipe-productivity competitor replacement | Yes |
| Compatibility architecture | Recipe-productivity ownership, family adoption, and known competitor replacement are modular and profile-driven rather than embedded in the generator | Yes |
| External compatibility audit | Mod-portal cataloging, dependency closure, executable manual scenarios, sharded lockfile runs, per-scenario timeouts, dependency-failure skipping, grouped expected/unexpected summaries, review-only profile stubs, strict/exploratory wrapper modes, and self-hosted workflow exist; full downloads/load checks remain local/manual with credentials | Yes |
| Icon source and asset policy | Fallback resolver can prefer loaded Space Age/Wube technology art, but the package does not redistribute original Space Age files | Yes |
| Scripted spoilage hardening | Existing-stack, reversal, disable, baseline, and multi-force behavior remains default-off with caveats until manual evidence exists | Yes |
| Scripted agriculture hardening | Newly planted crops stay in the default-off experimental path; existing-plant rescale remains out of scope | Yes |
| Compatibility matrix | Base, Space Age, Quality, custom science/lab, duplicate cargo/native modifier, and existing-save scenarios are recorded | Yes |
| Release evidence | README, compatibility docs, test results, changelog, package validation, and release notes agree | Yes |

## Feature Classification

| Feature | Classification | Implementation type | Default target |
| --- | --- | --- | --- |
| Checkbox enablement cleanup | Ship | Startup checkbox defaults plus shared resolver | `v2.1.0` |
| Shareable presets | Defer | Import/export or copyable settings profile design | Later |
| Broad native modifier overlap policy | Defer | Data-stage diagnostics plus future generation policy | Later |
| Known recipe-productivity competitor replacement | Ship | Prepare known competitors, generate MIR replacement effects, then remove only fully covered competing techs | `v2.1.0` |
| Vanilla Space Age productivity-family adoption | Ship | Add safe residual recipe effects into configured existing vanilla infinite technologies | `v2.1.0` |
| Compatibility audit harness | Ship as local tooling | Mod portal metadata, dependency lockfile, executable manual scenarios, optional download/load test, grouped expected/unexpected reports, sharding/resume, timeout protection, and self-hosted wrapper | `v2.1.0` |
| Generated audit rows | Ship | Parser-friendly diagnostics emitted with debug generation report | `v2.1.0` |
| Icon source resolver and asset policy | Ship | Data-stage icon candidate resolver plus package validation guard | `v2.1.0` |
| Spoilage preservation hardening | Defer stronger claims | Event-driven control-stage scripted tech | Later |
| Agricultural growth hardening | Defer stronger claims | Event-driven control-stage scripted tech | Later |
| Existing agricultural plant rescale | Defer | Research/configuration bounded tower scan with plant dedupe | Later if proven |
| High-throughput pump | Defer | Prototype unlock, no runtime loop | Later candidate |
| Pipeline extent multiplier | Implemented and validated for the conservative default and fixture coverage | Startup prototype setting, default 100%/unchanged | `v2.1.0` |
| Thruster fuel productivity | Implemented and validated | Recipe productivity | `v2.1.0` |
| Thruster oxidizer productivity | Implemented and validated | Recipe productivity | `v2.1.0` |
| Oil/fluid recipe productivity | Implemented and validated | Recipe productivity | `v2.1.0` |
| True thruster thrust research | Reject/defer | No clean native modifier lane | Not core MIR |
| Runtime platform speed mutation | Reject | Runtime hack | Not core MIR |
| Runtime quality odds mutation | Reject | Runtime hack/prototype mismatch | Not core MIR |
| Refrigeration/cold chain | Companion | New content loop | Separate mod |
| Greenhouses/off-world Gleba | Companion | New content loop | Separate mod |
| Super-bacteria | Companion | New content loop | Separate mod |
| Broad fluid overhaul | Defer/companion | Too broad | Separate or later |

## Settings Enablement

The shipped `v2.1.0` settings model keeps one enable path:

```text
Per-feature state:
- Enable checkbox on
- Enable checkbox off
```

Cost, growth, maximum level, and research unit time settings remain the existing manual tunables. Preset modes and per-feature enable-policy dropdowns are deferred because they added startup-setting noise without solving preset sharing.

Future preset work should be designed as an import/export or shareable settings profile flow, not as another override control beside every technology.

Acceptance criteria:

- Runtime fixtures validate checkbox-enabled and checkbox-disabled stream and base-extension decisions.
- Scripted runtime fixtures prove spoilage/agriculture effects use the same checkbox enablement as data-stage generation.
- README documents the single enablement path and the deferred shareable-preset direction.
- No generated technology IDs change without migration.

## Native Modifier Overlap Policy

`v2.0.5` reports native modifier overlaps diagnostically. `v2.1.0` keeps that broad native-modifier behavior diagnostic-only and ships narrower compatibility work where recipe ownership can be proven exactly.

Recommended setting:

```text
Native modifier overlap policy:
- Prefer existing owner
- Warn only
- Prefer MIR
- Allow duplicates
```

Recommended default:

```text
Prefer existing owner
```

Rationale: safer for overhaul mods and Maraxis-like mods that already provide equivalent cargo/logistics/native modifier research.

Acceptance criteria:

- Overlap diagnostics remain visible for cargo/logistics/native modifier cases.
- Exact recipe-productivity owners are respected before MIR generates replacement effects.
- Configured vanilla Space Age productivity families can adopt residual productivity-allowed recipes where the owner tech is safe.
- Known fully covered recipe-productivity competitor technologies are removed only after MIR replacement effects exist.
- Cargo landing pad and cargo unloading overlap fixtures remain diagnostic-only.
- README and compatibility docs explain the shipped narrow policy and the deferred broad policy plainly.

## Icon Source And Asset Policy

Keep MIR's current icon strategy: borrow the best active prototype icon, then add MIR's own effect-type badge. The `dev` line now has an explicit ordered `icon_candidates` resolver; keep improving that resolver instead of broadening the asset ownership boundary.

Allowed:

- Prefer loaded Space Age technology icons when `space-age` is active.
- Fall back to loaded base-game technology or item icons when Space Age is not active.
- Optionally use direct `__space-age__` icon paths when `mir-use-installed-space-age-icons` is enabled for a base game where the Space Age files are installed but the Space Age mod is disabled.
- Add an explicit icon-candidate registry so streams can say "prefer this Space Age technology, then this base technology, then this item" without duplicating lookup logic.
- Add MIR-owned fallback art only when the asset is original to MIR, generated for MIR, or otherwise clearly licensed for redistribution.
- Keep effect badges sourced from Factorio's technology constant icons when available, because those are already used as small modifier markers by MIR's generated technologies.

Not allowed in the main mod:

- Do not copy original Space Age PNGs or other DLC asset files into MIR so base-only games can display them.
- Do not make the base-only package behave as a Space Age art pack.
- Do not reference `__space-age__` paths in generated prototypes unless Space Age is loaded or the user explicitly enabled installed Space Age icon paths.
- Do not replace Wube's package ownership boundary with a local cache of their DLC assets.

Rationale: base-only games can have polished icons, but they should be base icons, MIR-owned icons, generated composites, or explicit references to locally installed Space Age files when the user opts in. MIR should not redistribute Space Age art.

Implementation shape:

```lua
icon_candidates = {
  { technology = "electric-weapons-damage-1", required_mod = "space-age" },
  { icon = "__space-age__/graphics/technology/electric-weapons-damage.png", icon_size = 256, inactive_mod_asset = "space-age" },
  { technology = "discharge-defense-equipment" },
  { item = "tesla-gun", required_mod = "space-age" }
}
```

The resolver should evaluate candidates in order, skip candidates whose required mod is not loaded, skip inactive asset candidates unless the user enabled them, copy the active prototype icon layers, strip inherited Wube constant overlays, and then apply MIR's own effect badge.

Acceptance criteria:

- Default base-only runtime fixtures never resolve generated technology icons to `__space-age__` paths.
- Opt-in base-only runtime fixtures with `mir-use-installed-space-age-icons` enabled resolve selected candidates to direct `__space-age__` icon paths.
- Space Age runtime fixtures still prefer the intended Space Age technology art when it is loaded.
- Package validation fails if MIR adds copied Space Age asset files under its own package paths without an explicit allowlisted source/license note.
- Diagnostics report the selected icon source as technology, item, explicit path, or MIR-owned local asset.
- README or compatibility docs explain that MIR references Space Age art only when Space Age is loaded.

## Scripted Spoilage Gate

Spoilage preservation uses Factorio's global spoil time modifier. Keep it conservative until manual evidence proves behavior in real saves.

Required manual results before stronger claims:

- newly created spoilable items;
- existing items on belts;
- existing items in chests;
- existing items in labs;
- existing items in rocket/platform inventories;
- partially spoiled stacks;
- research reversal;
- disabling and re-enabling the setting;
- multi-force behavior;
- interaction notes for other mods that mutate the same global setting.

Default recommendation until proven: keep Spoilage preservation off unless intentionally testing the scripted effect.

## Scripted Agriculture Gate

Newly planted agricultural tower crops are the stable first path. Existing plant rescale is conditional.

Existing plant rescale may ship only if:

- it runs only on research/configuration events;
- it does not scan every surface every tick;
- it scans agricultural towers, not arbitrary entities;
- it deduplicates plants because a plant can be owned by multiple towers;
- it batches or bounds work for large farms;
- large Gleba farm manual testing is recorded.

If those conditions are not met, keep `v2.0.5` behavior: newly planted crops only.

## High-Throughput Pump Gate

This is the cleanest megabase quality-of-life candidate if kept small.

Allowed scope:

- one high-throughput pump entity;
- finite or generated unlock;
- expensive recipe;
- high power draw;
- clear throughput description;
- no control-stage loop.

Out of scope for `v2.1.0`:

- pipe tiers;
- tank tiers;
- train/fluid overhaul;
- platform fluid overhaul;
- runtime fluid scripting.

## Implemented Expansion Gates

These features now have `v2.1.0` implementation coverage and automated fixture proof for the release claims. Non-conservative defaults, stronger balance recommendations, or broader manual compatibility claims still need save-level soak.

| Feature | Release proof status |
| --- | --- |
| Pipeline extent multiplier | Fixture validation proves the default `100%` path is inert and explicit non-default values mutate representative fluid boxes; large modded networks still need manual soak before recommending non-default values broadly |
| Thruster fuel productivity | Runtime fixtures prove exact recipe ownership and no duplicate infinite owner where the recipes exist |
| Thruster oxidizer productivity | Runtime fixtures prove exact recipe ownership and no duplicate infinite owner where the recipes exist |
| Oil/fluid productivity | Runtime fixtures prove oil-processing, cracking, lubricant, sulfuric-acid, acid-neutralisation, and Space Age propellant ownership behavior |
| Vanilla Space Age productivity-family adoption | Runtime fixtures prove safe adoption, conflict fallback, productivity-disallowed rejection, and existing-save effect refresh on signature changes |
| Plates n Circuit Productivity replacement | Runtime fixtures prove full replacement, partial coverage preservation, productivity-change mismatch preservation, and externally blocked combined-owner preservation |
| Agricultural yield | Clean event/prototype path exists without broad scans |
| Quality module enrichment | Clean prototype-tier/add-on path exists; no runtime module mutation |
| Roboport range | Native modifier exists or prototype-tier scope is clearly a companion feature |

## GitHub Milestone Checklist

Create a `v2.1.0` milestone and one issue per gate when GitHub milestone tooling is available.

Suggested issue titles:

- `v2.1.0: shareable settings profile design`
- `v2.1.0: native modifier overlap policy`
- `v2.1.0: spoilage preservation manual validation`
- `v2.1.0: agricultural growth manual validation`
- `v2.1.0: existing agricultural plant rescale spike`
- `v2.1.0: high-throughput pump prototype unlock`
- `v2.1.0: pipeline extent startup setting`
- `v2.1.0: thruster fuel and oxidizer productivity`
- `v2.1.0: oil/fluid recipe productivity`
- `v2.1.0: compatibility matrix`
- `v2.1.0: release packaging and docs`

Minimum issue template:

```markdown
## Goal

## Scope

## Out of scope

## Acceptance criteria

## Validation

## Release-note wording
```

## Definition Of Done

`v2.1.0` may release when:

- `info.json` is bumped to `2.1.0`;
- `changelog.txt` has a dated `2.1.0` entry;
- shareable settings profiles are explicitly deferred without shipping per-technology override dropdowns;
- native modifier overlap policy is implemented or explicitly deferred;
- scripted spoilage/agriculture stronger/default-on claims remain default-off unless backed by manual evidence;
- implemented expansion features are either shipped with proof or moved out of the release;
- no broad `on_tick` or `on_nth_tick` scanning is introduced;
- any generated technology ID changes have migrations;
- static/package validation passes;
- runtime fixture validation passes on Factorio `2.1.x`;
- branch policy validation passes;
- README, compatibility docs, roadmap, TODO, manual test plan, test results, changelog, and release notes agree.

# More Infinite Research 2.1.0 Release-Gated Plan

This document turns the post-`2.0.5` roadmap into an executable release gate for
the next Factorio `2.1` feature wave.

Primary rule:

```text
v2.1.0 = user-facing control + compatibility discipline + proof-gated expansion
```

Do not use `v2.1.0` as a bucket for every good Reddit or Discord idea. Every
feature must have a lane, an implementation type, and a validation gate before
code work starts.

## Release Theme

Ship the features that make MIR easier to control and safer in modded saves:

- simple per-technology checkbox enablement, with shareable presets deferred until there is an import/export design;
- a real native modifier overlap policy instead of diagnostics only;
- stricter icon source policy and fallback resolution;
- scripted spoilage/agriculture hardening with manual evidence;
- compatibility matrix updates;
- implemented fluid, thruster, and pipeline expansion gated by validation and manual balance evidence.

## Required Ship Gates

These are the core `v2.1.0` gates. The release should not ship without a clear
decision for each one.

| Gate | Required outcome | Release blocker? |
| --- | --- | ---: |
| Checkbox enablement | Per-technology enable checkboxes are the single source of truth for stream generation, base continuations, and scripted runtime effects | Yes |
| Shareable presets | Preset import/export remains deferred until it can be designed without adding per-technology override dropdowns | No |
| Native modifier overlap policy | Existing diagnostics become a policy: skip/prefer existing, warn only, prefer MIR, or allow duplicates | Yes |
| Icon source and asset policy | Fallback resolver can prefer loaded Space Age/Wube technology art, but the package does not redistribute original Space Age files | Yes |
| Scripted spoilage hardening | Existing-stack, reversal, disable, baseline, and multi-force behavior is measured or remains default-off with caveats | Yes |
| Scripted agriculture hardening | Newly planted crops are verified; existing-plant rescale either proves bounded or remains out of scope | Yes |
| Compatibility matrix | Base, Space Age, Quality, custom science/lab, duplicate cargo/native modifier, and existing-save scenarios are recorded | Yes |
| Release evidence | README, compatibility docs, test results, changelog, package validation, and release notes agree | Yes |

## Feature Classification

| Feature | Classification | Implementation type | Default target |
| --- | --- | --- | --- |
| Checkbox enablement cleanup | Ship | Startup checkbox defaults plus shared resolver | `v2.1.0` |
| Shareable presets | Defer | Import/export or copyable settings profile design | Later |
| Native modifier overlap policy | Ship | Data-stage diagnostics plus generation policy | `v2.1.0` |
| Icon source resolver and asset policy | Ship | Data-stage icon candidate resolver plus package validation guard | `v2.1.0` |
| Spoilage preservation hardening | Ship evidence/policy; maybe preset inclusion | Event-driven control-stage scripted tech | `v2.1.0` |
| Agricultural growth hardening | Ship evidence/policy; existing-plant rescale conditional | Event-driven control-stage scripted tech | `v2.1.0` |
| Existing agricultural plant rescale | Conditional | Research/configuration bounded tower scan with plant dedupe | `v2.1.0` if proven |
| High-throughput pump | Likely ship if kept small | Prototype unlock, no runtime loop | `v2.1.0` candidate |
| Pipeline extent multiplier | Implemented; ship if proof stays clean | Startup prototype setting, default 100%/unchanged | `v2.1.0` |
| Thruster fuel productivity | Implemented; ship if proof stays clean | Recipe productivity | `v2.1.0` |
| Thruster oxidizer productivity | Implemented; ship if proof stays clean | Recipe productivity | `v2.1.0` |
| Oil/fluid recipe productivity | Implemented; ship if proof stays clean | Recipe productivity | `v2.1.0` |
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

Cost, growth, maximum level, and research unit time settings remain the existing
manual tunables. Preset modes and per-feature enable-policy dropdowns are
deferred because they added startup-setting noise without solving preset
sharing.

Future preset work should be designed as an import/export or shareable settings
profile flow, not as another override control beside every technology.

Acceptance criteria:

- Runtime fixtures validate checkbox-enabled and checkbox-disabled stream and base-extension decisions.
- Scripted runtime fixtures prove spoilage/agriculture effects use the same checkbox enablement as data-stage generation.
- README documents the single enablement path and the deferred shareable-preset direction.
- No generated technology IDs change without migration.

## Native Modifier Overlap Policy

`v2.0.5` reports native modifier overlaps diagnostically. `v2.1.0` should turn
that into a user-facing policy.

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

Rationale: safer for overhaul mods and Maraxis-like mods that already provide
equivalent cargo/logistics/native modifier research.

Acceptance criteria:

- Overlap diagnostics remain visible.
- Default behavior avoids duplicate native infinite chains.
- Users can opt into duplicate behavior deliberately.
- Cargo landing pad and cargo unloading overlap fixtures pass.
- README and compatibility docs explain the policy plainly.

## Icon Source And Asset Policy

Keep MIR's current icon strategy: borrow the best active prototype icon, then add
MIR's own effect-type badge. The `dev` line now has an explicit ordered
`icon_candidates` resolver; keep improving that resolver instead of broadening
the asset ownership boundary.

Allowed:

- Prefer loaded Space Age technology icons when `space-age` is active.
- Fall back to loaded base-game technology or item icons when Space Age is not
  active.
- Optionally use direct `__space-age__` icon paths when
  `mir-use-installed-space-age-icons` is enabled for a base game where the Space
  Age files are installed but the Space Age mod is disabled.
- Add an explicit icon-candidate registry so streams can say "prefer this Space
  Age technology, then this base technology, then this item" without duplicating
  lookup logic.
- Add MIR-owned fallback art only when the asset is original to MIR, generated
  for MIR, or otherwise clearly licensed for redistribution.
- Keep effect badges sourced from Factorio's technology constant icons when
  available, because those are already used as small modifier markers by MIR's
  generated technologies.

Not allowed in the main mod:

- Do not copy original Space Age PNGs or other DLC asset files into MIR so
  base-only games can display them.
- Do not make the base-only package behave as a Space Age art pack.
- Do not reference `__space-age__` paths in generated prototypes unless Space
  Age is loaded or the user explicitly enabled installed Space Age icon paths.
- Do not replace Wube's package ownership boundary with a local cache of their
  DLC assets.

Rationale: base-only games can have polished icons, but they should be base
icons, MIR-owned icons, generated composites, or explicit references to locally
installed Space Age files when the user opts in. MIR should not redistribute
Space Age art.

Implementation shape:

```lua
icon_candidates = {
  { technology = "electric-weapons-damage-1", required_mod = "space-age" },
  { icon = "__space-age__/graphics/technology/electric-weapons-damage.png", icon_size = 256, inactive_mod_asset = "space-age" },
  { technology = "discharge-defense-equipment" },
  { item = "tesla-gun", required_mod = "space-age" }
}
```

The resolver should evaluate candidates in order, skip candidates whose required
mod is not loaded, skip inactive asset candidates unless the user enabled them,
copy the active prototype icon layers, strip inherited Wube constant overlays,
and then apply MIR's own effect badge.

Acceptance criteria:

- Default base-only runtime fixtures never resolve generated technology icons to
  `__space-age__` paths.
- Opt-in base-only runtime fixtures with `mir-use-installed-space-age-icons`
  enabled resolve selected candidates to direct `__space-age__` icon paths.
- Space Age runtime fixtures still prefer the intended Space Age technology art
  when it is loaded.
- Package validation fails if MIR adds copied Space Age asset files under its
  own package paths without an explicit allowlisted source/license note.
- Diagnostics report the selected icon source as technology, item, explicit
  path, or MIR-owned local asset.
- README or compatibility docs explain that MIR references Space Age art only
  when Space Age is loaded.

## Scripted Spoilage Gate

Spoilage preservation uses Factorio's global spoil time modifier. Keep it
conservative until manual evidence proves behavior in real saves.

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

Newly planted agricultural tower crops are the stable first path. Existing plant
rescale is conditional.

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

These features now have `v2.1.0` implementation coverage, but they still need
evidence before final release claims or non-conservative defaults.

| Feature | Required proof |
| --- | --- |
| Pipeline extent multiplier | Startup prototype mutation works and does not break machine/tank/modded pipe fluidboxes |
| Thruster fuel productivity | Exact recipes accept recipe productivity and no duplicate owner exists |
| Thruster oxidizer productivity | Exact recipes accept recipe productivity and no duplicate owner exists |
| Oil/fluid productivity | Fluid-only and mixed-output recipes behave correctly under recipe productivity |
| Agricultural yield | Clean event/prototype path exists without broad scans |
| Quality module enrichment | Clean prototype-tier/add-on path exists; no runtime module mutation |
| Roboport range | Native modifier exists or prototype-tier scope is clearly a companion feature |

## GitHub Milestone Checklist

Create a `v2.1.0` milestone and one issue per gate when GitHub milestone tooling
is available.

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
- scripted spoilage/agriculture claims are backed by manual evidence;
- implemented expansion features are either shipped with proof or moved out of the release;
- no broad `on_tick` or `on_nth_tick` scanning is introduced;
- any generated technology ID changes have migrations;
- static/package validation passes;
- runtime fixture validation passes on Factorio `2.1.x`;
- branch policy validation passes;
- README, compatibility docs, roadmap, TODO, manual test plan, test results,
  changelog, and release notes agree.

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

- settings presets with explicit override behavior;
- a real native modifier overlap policy instead of diagnostics only;
- stricter icon source policy and fallback resolution;
- scripted spoilage/agriculture hardening with manual evidence;
- compatibility matrix updates;
- only the spikes that prove cleanly.

## Required Ship Gates

These are the core `v2.1.0` gates. The release should not ship without a clear
decision for each one.

| Gate | Required outcome | Release blocker? |
| --- | --- | ---: |
| Settings presets | `Custom/manual`, `Vanilla-respectful`, `Megabase-balanced`, and `Unlimited sandbox` are implemented or explicitly deferred with rationale | Yes |
| Preset override model | User-visible precedence is documented and tested; presets do not silently contradict explicit per-feature choices | Yes |
| Native modifier overlap policy | Existing diagnostics become a policy: skip/prefer existing, warn only, prefer MIR, or allow duplicates | Yes |
| Icon source and asset policy | Fallback resolver can prefer loaded Space Age/Wube technology art, but the package does not redistribute original Space Age files | Yes |
| Scripted spoilage hardening | Existing-stack, reversal, disable, baseline, and multi-force behavior is measured or remains default-off with caveats | Yes |
| Scripted agriculture hardening | Newly planted crops are verified; existing-plant rescale either proves bounded or remains out of scope | Yes |
| Compatibility matrix | Base, Space Age, Quality, custom science/lab, duplicate cargo/native modifier, and existing-save scenarios are recorded | Yes |
| Release evidence | README, compatibility docs, test results, changelog, package validation, and release notes agree | Yes |

## Feature Classification

| Feature | Classification | Implementation type | Default target |
| --- | --- | --- | --- |
| Settings presets | Ship | Startup setting plus preset/default resolver | `v2.1.0` |
| Native modifier overlap policy | Ship | Data-stage diagnostics plus generation policy | `v2.1.0` |
| Icon source resolver and asset policy | Ship | Data-stage icon candidate resolver plus package validation guard | `v2.1.0` |
| Spoilage preservation hardening | Ship evidence/policy; maybe preset inclusion | Event-driven control-stage scripted tech | `v2.1.0` |
| Agricultural growth hardening | Ship evidence/policy; existing-plant rescale conditional | Event-driven control-stage scripted tech | `v2.1.0` |
| Existing agricultural plant rescale | Conditional | Research/configuration bounded tower scan with plant dedupe | `v2.1.0` if proven |
| High-throughput pump | Likely ship if kept small | Prototype unlock, no runtime loop | `v2.1.0` candidate |
| Pipeline extent multiplier | Spike only | Startup prototype setting | `v2.1.x` |
| Thruster fuel productivity | Spike only | Recipe productivity | `v2.1.x` |
| Thruster oxidizer productivity | Spike only | Recipe productivity | `v2.1.x` |
| Oil/fluid recipe productivity | Spike only | Recipe productivity | `v2.1.x` |
| True thruster thrust research | Reject/defer | No clean native modifier lane | Not core MIR |
| Runtime platform speed mutation | Reject | Runtime hack | Not core MIR |
| Runtime quality odds mutation | Reject | Runtime hack/prototype mismatch | Not core MIR |
| Refrigeration/cold chain | Companion | New content loop | Separate mod |
| Greenhouses/off-world Gleba | Companion | New content loop | Separate mod |
| Super-bacteria | Companion | New content loop | Separate mod |
| Broad fluid overhaul | Defer/companion | Too broad | Separate or later |

## Settings Presets

Recommended startup setting:

```text
MIR settings mode:
- Custom/manual
- Vanilla-respectful
- Megabase-balanced
- Unlimited sandbox
```

Preset intent:

| Preset | Intent |
| --- | --- |
| `Custom/manual` | Current behavior; individual settings control generation exactly |
| `Vanilla-respectful` | Conservative additions; no experimental/scripted/sandbox defaults; avoid aggressive uncapping |
| `Megabase-balanced` | Most reasonable late-game sinks enabled; risky scripted behavior still conservative |
| `Unlimited sandbox` | High-power options enabled or recommended with explicit warnings |

Avoid ambiguous precedence. Preferred model:

```text
Per-feature state:
- Use preset
- Force enabled
- Force disabled

Numeric setting state:
- Use preset/default
- Manual value
```

Do not make the UI say a feature is disabled while a preset silently enables it.

Acceptance criteria:

- Each preset has fixture or scripted validation for expected generated stream
  decisions.
- Existing `Custom/manual` behavior remains backward-compatible.
- README contains a preset comparison table.
- Setting tooltips explain precedence.
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
MIR's own effect-type badge. Improve the resolver, not the asset ownership
boundary.

Allowed:

- Prefer loaded Space Age technology icons when `space-age` is active.
- Fall back to loaded base-game technology or item icons when Space Age is not
  active.
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
- Do not reference `__space-age__` paths in generated prototypes unless the
  active mod set has loaded Space Age and the path is reachable.
- Do not replace Wube's package ownership boundary with a local cache of their
  DLC assets.

Rationale: base-only games can have polished icons, but they should be base
icons, MIR-owned icons, or generated composites. Space Age art should be used
by reference when Space Age is actually loaded.

Implementation shape:

```lua
icon_candidates = {
  { technology = "electric-weapons-damage-1", mod = "space-age" },
  { technology = "discharge-defense-equipment" },
  { item = "tesla-gun", mod = "space-age" }
}
```

The resolver should evaluate candidates in order, skip candidates whose required
mod is not loaded, copy the active prototype icon layers, strip inherited Wube
constant overlays, and then apply MIR's own effect badge.

Acceptance criteria:

- Base-only runtime fixtures never resolve generated technology icons to
  `__space-age__` paths.
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

Preset recommendation until proven:

| Preset | Spoilage preservation |
| --- | --- |
| `Vanilla-respectful` | Off |
| `Megabase-balanced` | Off unless manual evidence is strong |
| `Unlimited sandbox` | On or recommended |
| `Custom/manual` | User-controlled |

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

## Spike Gates

Spikes must produce an evidence note before promotion.

| Spike | Required proof |
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

- `v2.1.0: settings presets and override model`
- `v2.1.0: native modifier overlap policy`
- `v2.1.0: spoilage preservation manual validation`
- `v2.1.0: agricultural growth manual validation`
- `v2.1.0: existing agricultural plant rescale spike`
- `v2.1.0: high-throughput pump prototype unlock`
- `v2.1.0: pipeline extent startup setting spike`
- `v2.1.0: thruster fuel and oxidizer productivity spike`
- `v2.1.0: oil/fluid recipe productivity spike`
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
- settings presets and override behavior are implemented or explicitly deferred;
- native modifier overlap policy is implemented or explicitly deferred;
- scripted spoilage/agriculture claims are backed by manual evidence;
- conditional spikes are either promoted with proof or moved out of the release;
- no broad `on_tick` or `on_nth_tick` scanning is introduced;
- any generated technology ID changes have migrations;
- static/package validation passes;
- runtime fixture validation passes on Factorio `2.1.x`;
- branch policy validation passes;
- README, compatibility docs, roadmap, TODO, manual test plan, test results,
  changelog, and release notes agree.

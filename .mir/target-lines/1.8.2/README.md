# More Infinite Research 1.8.2

More Infinite Research 1.8.2 is the maintained Factorio 1.0 release.

It is a canonical MIR 3.1.9-derived target projection, feature-complete for the capabilities supported by the target Factorio engine. It is not identical to the Factorio 1.1 or 2.1 builds.

## Requirements

- Factorio 1.0, qualified on 1.0.0.
- `base >= 1.0`.
- No optional dependency is required.

## Included Research

MIR emits eleven stable, manifest-backed infinite research streams when their target effects are available:

- Character inventory capacity.
- Worker robot battery capacity.
- Laboratory productivity.
- Rocket, cannon, flamethrower, and electric weapon shooting speed.
- Character mining, crafting, walking, and reach bonuses.

MIR also extends supported Factorio 1.0 base infinite technology families for braking force, research speed, worker robot storage, weapon shooting speed, and laser turret shooting speed. Target-aware science selection uses Factorio 1.0 `tool` prototypes and rejects missing, disabled, cyclic, or unreachable prerequisites before emission.

## Weapon Ownership

Fresh installations default to `only-when-dedicated-tech-enabled`. MIR removes rocket and cannon-shell speed effects from its generated vanilla continuation only when a valid dedicated MIR or preferred exact external infinite owner exists. `off` and `always` remain available, and explicit values are preserved during the 1.8.1 to 1.8.2 upgrade.

## Settings

### Settings Guide

The Factorio 1.0 settings surface contains only controls with a target implementation:

- Per-stream enable, base cost, cost growth, maximum level, research time, and effect controls for retained streams.
- Enable and cost controls for retained base technology extensions.
- Lab incompatibility policy.
- Science-pack ingredient policy using Factorio 1.0 `tool` prototypes.
- Weapon overlap mode.

Unsupported controls are absent rather than inert. This release does not expose recipe-productivity, Space Age, Quality, recycler, cargo, prototype-limit, pipeline-extent, module-permission, settings-profile, automatic-family, or scripted-technology controls.

### What `0` Means

For maximum-level settings, `0` means the retained stream remains infinite. Other numeric controls require a positive value within the range shown by Factorio.

`Research unit time` is Factorio's seconds-per-research-unit value. It is not total completion time; total time also depends on research units, labs, lab speed, and modules.

## Compatibility Scope

Public compatibility claims are limited to the exact Factorio 1.0 qualification scenarios and named fixtures recorded with this release. MIR avoids mutating external infinite owners and does not claim broad compatibility with untested mod collections.

## Upgrade

The exact published 1.8.1 archive is the supported predecessor. The release gate verifies fresh load, save/reload, startup-setting retention, generated technology level, current research, fractional research progress, and `global` runtime-state retention on the matching binary.

## Installation

Place `more-infinite-research_1.8.2.zip` in the Factorio 1.0 `mods` directory. Do not unpack it.

The source repository contains maintainer documentation, fixtures, scripts, and evidence. Those files are intentionally excluded from the release ZIP.

## Evidence

Release identity and qualification details are recorded in:

- `docs/releases/1.8.2.md`
- `.mir/backport-source-lock.json`
- `.mir/evidence/1.8.2-qualification.json`
- `.mir/evidence/candidate-seals/mir-1.8.2-factorio-1.0.json`

Manual visual review remains separate from automated qualification and is not claimed unless a reviewer records it.

## Maintainer Source Checks

These commands apply to a source checkout; scripts and maintainer docs are excluded from the release ZIP:

```powershell
.\scripts\Invoke-MIRReleaseTargetedGate.ps1
.\scripts\mir.ps1 audit local
```

See `docs/maintainer/developer-tools.md` for the complete source-maintenance command reference.

---
title: "Settings"
status: current
applies_to: "3.0.0+"
audience: player
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-09
supersedes: []
superseded_by: []
---

# Settings

MIR uses startup settings for generated technology enablement, costs, caps,
science-pack policy, diagnostics, and prototype-stage options. Startup settings
are read during Factorio's prototype loading stages, so most generation choices
require a restart after changing them.

MIR-owned technology settings stay visible across base and Space Age so the
settings page is stable when toggling official DLC. Some exact third-party
provider settings may be hidden when their required provider mod is not
enabled. MIR still defines those setting keys internally so copied settings,
existing saves, and target-line backports can keep stable values. If the
relevant provider mod is enabled later, the setting can become visible again
with the saved value still available.

Use the in-game setting descriptions for exact defaults. Use
[settings reference](../reference/settings.md) for the canonical
technical contract once a setting needs maintainer-level detail.

Global settings are grouped with visible prefixes: Main, Compatibility,
Limits, Advanced, and Diagnostics. Some prefixes are color-emphasized
in-game for faster scanning, but the label text is still the structure.

Generated technology settings are ordered so default-off or experimental rows
come first, enabled special rows come next, and ordinary enabled rows come last.
Breeding, agricultural growth speed, cargo bay range/count, and character reach
are enabled by default but remain in the special row group. Inserter capacity
stays disabled by default because larger hand sizes can change circuit behavior
and inserter performance assumptions.

## Prototype Limit Settings

MIR includes four optional startup-only prototype limit settings:

- Recipe productivity cap
- Efficiency cap
- Speed effect cap
- Quality effect cap

The unchanged dropdown entries are value-first labels: `300% (unchanged)` for
recipe productivity, `80% savings (unchanged)` for efficiency, and
`+100000% (unchanged)` for speed and quality. Those unchanged entries leave the
relevant Factorio prototype fields alone. Non-default values are explicit global
balance overrides for long-running infinite research saves or modpacks that want
stricter or broader module-effect ceilings.

These settings apply during prototype loading and require a restart after
changing them. They do not add per-tick runtime processing, and they are not
part of MIR's generated technology planner. The quality cap changes only the
machine quality-effect ceiling; it does not change quality-tier probabilities.

## Portable Settings Profiles

MIR can export a portable settings profile for the current effective MIR startup
settings. Use this when you are changing modpacks, removing an overhaul,
temporarily disabling Space Age, testing a backport branch, or moving settings
between saves.

From an active save, run:

```text
/mir-settings-export
```

or:

```text
/mir-settings-export my-pack-name
```

Factorio writes the profile to:

```text
script-output/more-infinite-research/settings/<name>.txt
```

To import a profile, paste the exported string into the startup setting:

```text
mir-settings-profile-import
```

then restart Factorio so MIR can apply the profile during prototype generation.
The imported profile is an override layer for MIR's own startup-setting reads;
it does not delete the normal setting prototypes or rewrite Factorio's
`mod-settings.dat`.

You can validate a pasted profile before using it:

```text
/mir-settings-import-check <profile-string>
```

The validation command reports how many setting IDs are recognized by the
current branch and how many are unavailable or ignored. Unknown settings remain
inside the profile string, so the same profile can still be useful when you
reenable a provider mod or move back to a branch that knows those setting IDs.

MIR does not use a direct OS clipboard or arbitrary file-import API. Factorio
runtime code can write export files under `script-output`, while import happens
through the stable startup setting above.

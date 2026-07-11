---
title: "Settings"
status: current
applies_to: "3.0.0+"
audience: player
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-11
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

MIR includes startup-only prototype limit settings:

- Recipe productivity cap
- Generated recycler return rate
- Energy savings cap
- Pollution reduction cap
- Minimum machine speed
- Speed effect cap
- Quality effect cap

When the productivity cap is selected above +300%, the default-off
`mir-productivity-cap-self-recycling-only` checkbox limits MIR's upward cap
mutation to recipes with a proven single-item self-recycling path whose
expected loop is non-generative. Unsafe recipes keep their existing cap, and
MIR never raises the recycling recipe itself. The checkbox has no effect at
+300% or below.

The `mir-recycling-return-chance` dropdown is a separate balance control for
hidden generated recycling recipes. `Match productivity cap (safe)` uses the
inverse of total capped output, `1 / (1 + bonus)`, and never raises the normal
25% return. That means +400% productivity uses a 20% recycler return and
+1000% uses about 9.09%. Fixed 25%, 20%, 15%, 12.5%, 10%, 7.5%, 5%, 2.5%,
1%, 0.5%, and 0.1% choices are also available. Visible processes such as scrap recycling are intentionally
excluded.

The experimental `mir-unrestricted-modules` Compatibility setting opens all
five module effect types and every discovered module category on recipes and
existing module receivers that already have slots, including beacons. It does
not add slots or change module prototypes and can create severe productivity,
quality, and modded-module balance exploits.

Every dropdown has a neutral option that bypasses its optional transformation.
The prototype-limit entries are value-first labels: `+300% (unchanged)` for
recipe productivity, `-80% (unchanged)` for energy and pollution reductions,
and `+100000% (unchanged)` for speed and quality. Science-pack `configured`,
weapon-speed cleanup `off`, pipeline `100%`, and lab compatibility
`engine-default` are the other neutral paths. Those unchanged entries leave the
relevant Factorio prototype fields alone. Non-default values are explicit global
balance overrides for long-running infinite research saves or modpacks that want
stricter or broader module-effect ceilings.

Minimum machine speed is independent from the positive speed-effect cap. Its
unchanged value is -80%; the dropdown spans -25%, -50%, -75%, and deeper floors
as far as -99.99%,
which is a near-stop but not zero or negative crafting speed.

The consistent broad ladders reach 1000% for pipeline extent, +100000% for
productivity, +25000% as an explicit speed or quality override (with the engine's
+100000% ceiling available through unchanged), and -99.99% for negative effect
limits. Existing option IDs remain valid for imported profiles and backports.

Advanced portable profiles can use any valid decimal percentage within the
setting's safe bounds even when that value is not listed in the dropdown. Use a
JSON number in displayed percentage units, such as `123.45` or `-83.25`; invalid
or out-of-range values are ignored. The in-game dropdown remains curated for
easy selection.

For the exact option list and a count of every checkbox, dropdown, numeric field,
and text setting in 3.0.5, see the
[3.0.5 settings inventory](../releases/3.0.5-settings-inventory.md).

Module productivity discovers final `module` prototypes by their declared
tier. Tiers 1, 2, and 3 keep the existing +10%, +5%, and +2% per-level values;
tier 4 and later module recipes receive +1% per level. This includes modded
module categories without requiring name patterns or a per-mod checkbox.

Use the energy savings cap when a modpack's beacon, module, or quality effects
can push machines toward near-zero active power draw. The pollution reduction
cap is separate because efficiency modules can reduce both energy use and
pollution, while modpacks may want different floors for each effect.

The strongest selectable reduction is `-99.99%`. Factorio's effect receiver
prototype bounds do not allow a literal `-100%` effect limit.

The Non-zero power floor is a separate Compatibility setting, not a Limits
cap. Use it only when a modpack has explicit `0W` active-use entity prototypes
that create unwanted low-power warning icons. When enabled, MIR changes those
explicit `0W` `energy_usage` prototypes to `1W` during prototype loading.
Leave it off to preserve zero-power prototypes exactly.

## Generated Technology Effect Settings

Each generated technology has an `Effect per level` setting beside
its cost and level controls. Its default is the primary, base-tier effect—the
first tier shown by MIR's technology contract. Changing it scales all related
tiers and effects proportionally, preserving ratios such as a technology with
+10%, +5%, and +2% effects. Optional later tiers no longer make the displayed
default unexpectedly small. Percentage effects use
percentage points; slots, counts, and distances use their native units. The
enable checkbox remains the way to disable a technology—zero is not a disable
value.

For scripted multiplier technologies, such as spoilage preservation and
agricultural growth speed, the setting scales the per-level delta. A selected
2% effect therefore becomes a `1.02` multiplier per level; MIR never multiplies
the full canonical `1.01` value.

These settings require a restart after changing them. Numeric prototype effects
are applied during prototype loading; existing bounded scripted handlers read
their selected delta at runtime. The quality cap changes only the
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
current branch, how many values are invalid, and how many IDs are unavailable
or ignored. Unknown settings remain inside the profile string, so the same
profile can still be useful when you reenable a provider mod or move back to a
branch that knows those setting IDs.

For shorter strings, run:

```text
/mir-settings-export --compact my-pack-name
```

Compact export omits settings that still equal MIR's catalog default. Full
export remains the default because it is easier to audit.

MIR does not use a direct OS clipboard or arbitrary file-import API. Factorio
runtime code can write export files under `script-output`, while import happens
through the stable startup setting above.

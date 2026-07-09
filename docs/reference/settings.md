---
title: "Settings Reference"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-09
supersedes: [docs/reference/settings-reference.md]
superseded_by: []
---

# Settings Reference

This page is the maintainer-level reference for MIR startup settings. Player
guidance belongs in [user settings](../user/settings.md). Governance rules live
in [settings governance](../maintainer/settings-governance.md), and the
machine-readable policy is `.mir/settings.yml`.

## Contract

MIR keeps every released setting prototype registered. MIR-owned official
technology settings stay visible across base and Space Age so players get a
stable settings surface. Exact third-party provider settings may be hidden when
the provider mod is absent, but MIR must not delete setting IDs because an
optional provider mod is absent.

Governed technology settings preserve the same keys:

```text
ips-enable-<stream>
ips-cost-base-<stream>
ips-cost-growth-<stream>
ips-max-level-<stream>
ips-research-time-<stream>
```

MIR uses `hidden = true` only for provider-specific or unsupported stream
settings. It does not use `forced_value` for those settings, because the user's
saved value should return if the relevant mod or expansion is enabled again.

MIR also registers the global startup setting:

```text
mir-settings-profile-import
```

This setting accepts a portable MIR settings profile string. It is always
registered and stays out of profile exports so importing one profile never
nests another profile inside it.

## Visibility

Stream visibility is declared with `ui_visibility` metadata. The settings stage
may evaluate active mods and static metadata only; it must not inspect
`data.raw` recipes, items, fluids, technologies, labs, or machines.

Supported visibility modes:

- `always`: show the setting group. Use this for MIR-owned official streams,
  including Space Age-shaped streams whose generation may skip in base games.
- `hidden`: hide the setting group by policy.
- `visible-if-mods-any`: show when any named provider mod is enabled.
- `visible-if-mods-all`: show when every named provider mod is enabled.
- `visible-if-mods-any-or-always-on-base`: show for base-visible streams or
  when any named provider mod is enabled.

Example:

```lua
ui_visibility = {
  mode = "visible-if-mods-any",
  mods_any = {"atan-air-scrubbing"},
  hidden_reason = "requires-atan-air-scrubbing"
}
```

## Ordering

Global startup settings use visible section prefixes and stable `a-*` order
ranges:

| Range | Visible prefix | Purpose |
| --- | --- | --- |
| `a-0-*` | Main | Main behavior settings |
| `a-1-*` | Compatibility | Compatibility behavior and prototype compatibility passes |
| `a-2-*` | Limits | Explicit prototype cap overrides |
| `a-7-*` | Advanced | Settings profile import and future advanced controls |
| `a-8-*` | Diagnostics | Log and audit controls |

The visible prefixes may use Factorio rich text for color and bold emphasis,
but the plain section words remain part of the label. Do not add fake divider
settings for 3.0.0.

Generated technology settings use three `b-*` buckets:

- `b-000`: disabled-by-default or experimental rows;
- `b-050`: enabled special, unusual, balance-sensitive, or vanilla-continuation
  rows;
- `b-100`: ordinary enabled rows.

Breeding productivity, agricultural growth speed, cargo bay unloading distance,
cargo landing pad count, and character reach are enabled by default but remain
in the special bucket. Inserter capacity bonus remains disabled by default and
therefore stays in the first bucket.

## Prototype Limit Settings

Prototype limit settings are startup-only explicit overrides. Their internal
default value is `engine-default`, which means no prototype mutation. In the
settings UI, the unchanged options are labelled as concrete values:
`300% (unchanged)` for recipe productivity, `80% savings (unchanged)` for
efficiency, and `+100000% (unchanged)` for speed and quality effect caps.

| Setting ID | Non-default target |
| --- | --- |
| `mir-prototype-productivity-cap` | `RecipePrototype.maximum_productivity` on non-parameter recipes |
| `mir-prototype-efficiency-cap` | `effect_receiver.consumption_limits.low` on supported machines, labs, drills, and agricultural towers |
| `mir-prototype-speed-cap` | `effect_receiver.speed_limits.high` on supported machines, labs, drills, and agricultural towers |
| `mir-prototype-quality-cap` | `effect_receiver.quality_limits.high` on supported machines, labs, drills, and agricultural towers |

The energy savings cap is the supported 3.0.0 control for modpacks where
stacked beacon, module, or quality effects can make machine energy use approach
zero. Selecting `75% savings` or `50% savings` writes a stricter
`consumption_limits.low` floor on supported effect receivers. MIR does not add
a separate runtime power-use correction loop.

The prototype limit pass runs in `data-final-fixes` after exact compatibility
repairs and before MIR planning. That keeps upstream schema normalization first,
then lets generated technology planning and diagnostics observe the selected
limits. The quality cap does not mutate `QualityPrototype` probability fields.

## Generation

Visibility does not prove that a stream can generate. Data-stage generation
must still validate final prototype facts such as target recipes, item or fluid
existence, science packs, lab compatibility, recipe caps, ownership, loop risk,
and prerequisites.

Use `generation_requirements` for governed data-stage intent:

```lua
generation_requirements = {
  require_any_recipe = {"atan-pollution-filter", "atan-spore-filter"},
  deny_risk_flags = {"scrubbing_environmental", "cleaning_recovery"}
}
```

The current legacy generator still uses the existing stream fields such as
`required_mods`, `required_items`, `required_fluids`, `recipe_patterns`, and
`items` for runtime behavior. `generation_requirements` records the MIR 3
contract separately so the settings UI does not become a proxy for final target
truth.

## Backports

Backport branches keep the same setting IDs where possible. Unsupported
provider-specific settings should be registered and hidden instead of removed.
If a string setting has values meaningful only on a newer line, the older line
should accept the value and map it to a safe data-stage fallback rather than
narrowing `allowed_values` and causing settings-load failures.

Use `forced_value` only for documented safety-invalid or deprecated settings
where the previous value must not apply.

## Portable Profile Format

The profile codec lives in `prototypes/mir/settings/profile_codec.lua`.
Profiles are encoded as:

```text
MIRSET1:<encoded-json>
```

The decoded payload has schema `1`:

```json
{
  "schema": 1,
  "kind": "mir-settings-profile",
  "mod": "more-infinite-research",
  "metadata": {
    "mir_version": "3.0.0",
    "factorio_version": "2.1.x",
    "import_setting": "mir-settings-profile-import"
  },
  "settings": {
    "ips-enable-research_tungsten": true,
    "ips-max-level-research_tungsten": 0
  }
}
```

Only setting names beginning with `ips-` or `mir-` are exported, and
`mir-settings-profile-import` is explicitly excluded. The codec accepts either
the `MIRSET1:` encoded form or raw JSON for maintainer debugging.

`prototypes/mir/settings/effective.lua` reads the import setting once during
prototype loading. An imported value applies only when:

- the profile schema is supported;
- the setting exists in the current branch;
- the setting is not `mir-settings-profile-import`;
- the imported value has the same Lua type as the current setting value.

Unknown setting IDs and mismatched value types are ignored on the current run,
not removed from the profile. That keeps profiles portable across optional-mod
changes and target-line backports.

Runtime command support lives in `prototypes/mir/runtime/settings_profile.lua`:

- `/mir-settings-export [name]` writes the current effective profile to
  `script-output/more-infinite-research/settings/<name>.txt`;
- `/mir-settings-import-check <profile-string>` validates a pasted profile
  against the currently registered settings;
- remote interface `more-infinite-research-settings.export_string()` returns an
  encoded profile string for other tools;
- remote interface `more-infinite-research-settings.validate_string(text)`
  validates a candidate profile.

Runtime commands do not mutate startup settings. Users still paste the profile
into `mir-settings-profile-import` and restart for data-stage generation to use
it.

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
| `a-1-*` | Compatibility | Compatibility behavior and prototype compatibility passes, including the default-off non-zero power floor |
| `a-2-*` | Limits | Explicit numeric prototype cap overrides |
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

Prototype limit settings are startup-only explicit numeric overrides. Their internal
default value is `engine-default`, which means no prototype mutation. In the
settings UI, the unchanged options are labelled as concrete values:
`+300% (unchanged)` for recipe productivity, `-80% (unchanged)` for energy and
pollution reductions, and `+100000% (unchanged)` for speed and quality effect
caps. Numeric dropdowns are ordered highest to lowest with the unchanged
default in its numeric position.

| Setting ID | Non-default target |
| --- | --- |
| `mir-prototype-productivity-cap` | `RecipePrototype.maximum_productivity` on non-parameter recipes |
| `mir-prototype-efficiency-cap` | `effect_receiver.consumption_limits.low` on supported machines, labs, drills, and agricultural towers |
| `mir-prototype-pollution-cap` | `effect_receiver.pollution_limits.low` on supported machines, labs, drills, and agricultural towers |
| `mir-prototype-speed-cap` | `effect_receiver.speed_limits.high` on supported machines, labs, drills, and agricultural towers |
| `mir-prototype-quality-cap` | `effect_receiver.quality_limits.high` on supported machines, labs, drills, and agricultural towers |

Efficiency modules can reduce both energy use and pollution, but MIR exposes
those floors separately because modpacks may want different behavior for active
power draw and pollution output. The strongest selectable reduction is
`-99.99%`; Factorio's effect receiver bounds do not allow a literal `-100%`
lower limit. MIR does not add a runtime power-use correction loop.

The non-zero power floor is a default-off Compatibility setting, not a Limits
cap. It scans prototype tables only when enabled and changes explicit `0W`
active `energy_usage` fields to `1W`. This is intentionally separate from
`consumption_limits.low`: effect limits control module/beacon/surface effects,
while the power floor preserves machines that should draw a tiny non-zero
amount and suppresses unwanted zero-power warning icons.

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

The canonical settings catalog lives in `prototypes/mir/settings/catalog.lua`.
Registration, profile export, import validation, and tests use that catalog for
setting IDs, defaults, allowed values, and numeric bounds.

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
  "format": 1,
  "codec": "canonical-json-deflate-base64",
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

Only cataloged setting names beginning with `ips-` or `mir-` are exported, and
`mir-settings-profile-import` is explicitly excluded. Full export is the safe
default. `/mir-settings-export --compact [name]` omits settings that still
equal the catalog default. The codec accepts either the `MIRSET1:` encoded form
or raw JSON for maintainer debugging.

The encoded JSON is canonicalized before compression: object keys are sorted,
schema `1` carries explicit `format` and `codec` fields, and future schema
migration is centralized in the codec's decode path.

`prototypes/mir/settings/effective.lua` reads the import setting once during
prototype loading. An imported value applies only when:

- the profile schema is supported;
- the setting exists in the current branch;
- the setting is not `mir-settings-profile-import`;
- the imported value matches the catalog setting type;
- string values are in the allowed-value set or documented legacy import set;
- numeric values fit the catalog minimum and maximum bounds.

Unknown setting IDs, wrong value types, invalid enum values, and out-of-range
numbers are ignored on the current run, not removed from the profile. That keeps
profiles portable across optional-mod changes and target-line backports without
coercing unsafe values.

Runtime command support lives in `prototypes/mir/runtime/settings_profile.lua`:

- `/mir-settings-export [name]` writes the current effective full profile to
  `script-output/more-infinite-research/settings/<name>.txt`;
- `/mir-settings-export --compact [name]` writes only non-default settings;
- `/mir-settings-import-check <profile-string>` validates a pasted profile
  against the currently registered catalog settings;
- remote interface `more-infinite-research-settings.export_string()` returns an
  encoded profile string for other tools;
- remote interface `more-infinite-research-settings.export_string({compact =
  true})` returns a compact encoded profile string;
- remote interface `more-infinite-research-settings.validate_string(text)`
  validates a candidate profile.

Runtime commands do not mutate startup settings. Users still paste the profile
into `mir-settings-profile-import` and restart for data-stage generation to use
it.

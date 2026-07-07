---
title: "Settings Reference"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-08
supersedes: [docs/reference/settings-reference.md]
superseded_by: []
---

# Settings Reference

This page is the maintainer-level reference for MIR startup settings. Player
guidance belongs in [user settings](../user/settings.md). Governance rules live
in [settings governance](../maintainer/settings-governance.md), and the
machine-readable policy is `.mir/settings.yml`.

## Contract

MIR keeps every released setting prototype registered. It may hide startup
settings that are not actionable for the current enabled mod set, but it must
not delete setting IDs because an optional provider mod is absent.

Hidden unavailable technology settings preserve the same keys:

```text
ips-enable-<stream>
ips-cost-base-<stream>
ips-cost-growth-<stream>
ips-max-level-<stream>
ips-research-time-<stream>
```

MIR uses `hidden = true` for normal unavailable stream settings. It does not use
`forced_value` for those settings, because the user's saved value should return
if the relevant mod or expansion is enabled again.

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

- `always`: show the setting group.
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
settings should be registered and hidden instead of removed. If a string setting
has values meaningful only on a newer line, the older line should accept the
value and map it to a safe data-stage fallback rather than narrowing
`allowed_values` and causing settings-load failures.

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

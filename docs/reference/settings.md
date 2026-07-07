---
title: "Settings Reference"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-07
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

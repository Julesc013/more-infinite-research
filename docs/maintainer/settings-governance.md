---
title: "Settings Governance"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Settings Governance

Settings are compatibility surface. Treat a released setting ID like a public
contract unless there is a documented migration reason to retire it.

## Rules

- Keep released setting IDs registered.
- Hide unavailable stream settings instead of deleting them.
- Do not use `forced_value` for normal unavailable technology streams.
- Keep settings-stage visibility based on `ui_visibility` metadata and active
  mods only.
- Keep data-stage generation based on final prototype facts.
- Record governed setting policy in `.mir/settings.yml`.
- Keep broad global settings visible unless they are deprecated or unsafe.

## Adding A Stream Setting

1. Add or confirm the stream ID.
2. Keep the generated setting names stable:
   `ips-enable-<stream>`, `ips-cost-base-<stream>`,
   `ips-cost-growth-<stream>`, `ips-max-level-<stream>`, and
   `ips-research-time-<stream>`.
3. Add `ui_visibility` to the stream when it is useful only with known provider
   mods.
4. Add `generation_requirements` for the data-stage intent.
5. Add or update the row in `.mir/settings.yml`.
6. Add fixture or static validation if the stream should be hidden without its
   provider.

## Provider Visibility

Use this pattern for exact optional-provider streams:

```lua
ui_visibility = {
  mode = "visible-if-mods-any",
  mods_any = {"provider-mod"},
  hidden_reason = "requires-provider-mod"
}
```

Use `always` for base-game or generic streams with base targets. For example,
transport belt productivity stays visible in a base game because base belts
exist even when loader mods are absent.

## Backports

Backport branches keep released setting IDs where possible. If a branch cannot
support a stream, register the setting and hide it. If a saved string value is
newer than the branch can act on, accept it and map it to a safe fallback during
the data stage instead of narrowing `allowed_values`.

This policy supports:

- `3.0.0` on the main Factorio 2.1 line;
- later `2.3.0` backports;
- later `1.9.3` legacy backports.

Do not update already-published release archives just to change setting
governance docs or manifests.

## Validation

Run the static gate after settings changes:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

The static gate runs `scripts/Test-MIRSettingsVisibility.ps1`. The runtime gate
also enables `mir-fixture-assert-hidden-setting-readability` in the base
generation scenario to prove hidden optional-stream settings remain registered
and readable during `data-final-fixes.lua`.

Run the runtime gate before release:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\path\to\factorio.exe"
```

Manual value-retention proof for an optional stream:

1. Enable the provider mod or expansion.
2. Set custom values for the stream's enable, cost, growth, cap, and time
   settings.
3. Restart without the provider.
4. Confirm the stream settings are hidden.
5. Re-enable the provider.
6. Confirm the custom values return.

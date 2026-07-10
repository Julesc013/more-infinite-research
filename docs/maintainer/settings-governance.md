---
title: "Settings Governance"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-09
supersedes: []
superseded_by: []
---

# Settings Governance

Settings are compatibility surface. Treat a released setting ID like a public
contract unless there is a documented migration reason to retire it.

## Rules

- Keep released setting IDs registered.
- Keep MIR-owned official technology settings visible across base and Space
  Age, even when the current active mod set cannot generate that technology.
- Hide exact third-party provider stream settings when the provider mod is not
  active instead of deleting them.
- Do not use `forced_value` for normal unavailable technology streams.
- Keep settings-stage visibility based on `ui_visibility` metadata and active
  mods only. It must not inspect final prototype facts.
- Keep data-stage generation based on final prototype facts.
- Record governed setting policy in `.mir/settings.yml`.
- Add new setting IDs to `prototypes/mir/settings/catalog.lua` before using
  them in registration, profile export/import, docs, or tests.
- Keep broad global settings visible unless they are deprecated or unsafe.
- Preserve portable profile import/export compatibility by keeping
  `mir-settings-profile-import` registered.
- Exclude `mir-settings-profile-import` from exported profiles.
- Treat a profile import as an effective data-stage override, not a runtime
  mutation of Factorio startup settings.
- Order technology settings in three attention buckets: default-off or
  experimental rows first, enabled special/unusual rows second, and ordinary
  enabled rows last. Sort alphabetically inside each bucket.
- Keep prototype limit settings startup-only, defaulting to `engine-default`,
  and document every non-default value as an explicit global prototype override.
- Keep energy-use limits, pollution limits, and zero-power prototype rewrites as
  separate controls. The zero-power rewrite must remain default off.
- Use visible section prefixes and order ranges for global settings. Do not add
  fake divider settings.
- Treat rich text in setting labels as a visual enhancement only; the plain
  section words must still be readable if styling is not rendered.

## Adding A Stream Setting

1. Add or confirm the stream ID.
2. Keep the generated setting names stable:
   `ips-enable-<stream>`, `ips-cost-base-<stream>`,
   `ips-cost-growth-<stream>`, `ips-max-level-<stream>`, and
   `ips-research-time-<stream>`.
3. Use `ui_visibility = { mode = "always" }` for MIR-owned official streams,
   including Space Age-shaped streams. Add provider-gated `ui_visibility` only
   when the setting is useful only with a specific third-party mod.
4. Add `generation_requirements` for the data-stage intent.
5. Add or update the row in `.mir/settings.yml`.
6. Add fixture or static validation if the stream should be hidden without its
   provider, or if the stream must remain visible across base and Space Age.

## Provider Visibility

Use `always` for official or MIR-owned technology rows, including rows that
will only generate when Space Age prototypes are active. Data-stage generation
still skips unavailable candidates with clear diagnostics.

Use this pattern for exact optional-provider streams:

```lua
ui_visibility = {
  mode = "visible-if-mods-any",
  mods_any = {"provider-mod"},
  hidden_reason = "requires-provider-mod"
}
```

Transport belt productivity is also `always`: base belts exist in base games
and loader recipes are opportunistic additions.

## Attention Ordering

Global startup settings use the order helper in
`prototypes/mir/settings/order.lua`:

- `Main`: main behavior settings;
- `Compatibility`: compatibility behavior and prototype compatibility passes,
  including the default-off non-zero power floor;
- `Limits`: explicit global numeric prototype cap overrides;
- `Advanced`: profile import and future advanced controls;
- `Diagnostics`: log and audit controls.

Use these visible prefixes instead of fake section rows. Fake dividers are real
settings, can be clicked, and make the settings UI noisier.

Use the `settings_priority = "top"` stream or base-extension default for
enabled technologies that are unusual, balance-sensitive, scripted, or
important enough to keep above the ordinary generated technology list. Disabled
or experimental rows still sort above that middle bucket because players should
see opt-in risk first.

In 3.0.0, breeding productivity, agricultural growth speed, cargo bay unloading
distance, cargo landing pad count, and character reach are enabled by default
but stay in the special bucket. Inserter capacity bonus also stays near the top
but remains disabled by default because larger inserter hand sizes can break
circuit-controlled inserters and reduce engine optimization assumptions.

## Prototype Limit Settings

Prototype limit settings must be visible global settings, not hidden behavior.
`engine-default` means MIR does not touch the corresponding Factorio prototype
field. Player-facing labels should show the effective unchanged cap, such as
`+300% (unchanged)` for recipe productivity or `-80% (unchanged)` for energy
or pollution reductions, instead of exposing the internal value. Non-default
values may mutate recipe productivity caps or effect receiver limits during
`data-final-fixes`, but they must not require runtime event processing.

Do not couple the non-zero power floor to the energy savings cap. It is a
Compatibility setting because it is an opt-in prototype compatibility
workaround, not a numeric cap. The energy
savings cap writes `effect_receiver.consumption_limits.low`; the pollution cap
writes `effect_receiver.pollution_limits.low`; the default-off power-floor
checkbox changes explicit `0W` active `energy_usage` prototypes to `1W`.

Keep the implementation in the MIR settings and pipeline layers. Compatibility
policy files may not apply these overrides directly.

## Backports

Backport branches keep released setting IDs where possible. If a branch cannot
support a stream at all, register the setting and hide it. If a saved string
value is newer than the branch can act on, accept it and map it to a safe
fallback during the data stage instead of narrowing `allowed_values`.

This policy supports:

- `3.0.0` on the main Factorio 2.1 line;
- later `2.3.0` backports;
- later `1.9.3` legacy backports.

Do not update already-published release archives just to change setting
governance docs or manifests.

## Portable Profiles

Portable settings profiles exist so players can keep MIR preferences while
changing optional mods, changing overhaul packs, downgrading to a supported
target line, or returning to a newer line later.

The contract:

- exported profiles use the `MIRSET1:` prefix and schema `1`;
- exports include cataloged MIR startup setting IDs beginning `ips-` or `mir-`;
- exports exclude `mir-settings-profile-import`;
- full export is the default;
- compact export is opt-in through `/mir-settings-export --compact` and omits
  values that still match the catalog default;
- profile JSON is emitted in canonical key order before compression so repeated
  exports of the same settings are deterministic;
- imports apply only to current registered setting IDs whose values pass
  catalog type, allowed-value, and numeric-bound checks;
- unknown profile entries are ignored on the current branch and left in the
  string for future use;
- wrong-type, invalid-enum, and out-of-range profile values are ignored rather
  than coerced;
- invalid profile strings are logged and ignored;
- runtime commands may export or validate profiles but must not attempt to
  rewrite startup setting values.

Profile serialization and reduced-target visibility are separate contracts.
`settings-profile-roundtrip` runs only where the profile codec is shipped and
checks canonical encoding, compact export, and strict import validation.
`reduced-settings-surface` runs on reduced lines where profiles are omitted and
checks that supported settings remain available while modern-only settings are
absent. A locally constructed placeholder string is not profile-codec evidence.

Do not narrow an existing string setting's `allowed_values` on a backport line
unless there is no safe data-stage fallback. Prefer accepting the value and
mapping unsupported choices to a documented safe behavior.

When a setting is renamed, keep the old ID as a hidden compatibility alias until
a documented migration proves that dropping it cannot lose user intent. If the
old setting must be retired, document the reason and the profile behavior in
this page and `.mir/settings.yml`.

## Validation

Run the static gate after settings changes:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

The static gate runs `scripts/Test-MIRSettingsVisibility.ps1`, which discovers
every stream key from `prototypes/streams/*.lua` and requires a generated
settings sort label plus hidden-setting readability fixture coverage. The
runtime gate also enables `mir-fixture-assert-hidden-setting-readability` in
base, Space Age, and named provider-mod compatibility scenarios to prove stream
and base-extension startup settings remain registered and readable during
`data-final-fixes.lua`.

Run the runtime gate before release:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\path\to\factorio.exe"
```

Manual value-retention proof for an optional stream:

1. Enable the provider mod or expansion.
2. Set custom values for the stream's enable, cost, growth, cap, and time
   settings.
3. Restart without the provider.
4. Confirm provider-specific stream settings are hidden; official MIR settings
   should stay visible.
5. Re-enable the provider.
6. Confirm the custom values return.

Manual profile proof:

1. Configure several MIR stream and global startup settings.
2. Start a save and run `/mir-settings-export profile-proof`.
3. Copy the profile string from
   `script-output/more-infinite-research/settings/profile-proof.txt`.
4. Paste it into `mir-settings-profile-import`.
5. Restart with a different optional-mod set.
6. Run `/mir-settings-import-check <profile-string>` in a save to confirm the
   recognized and ignored counts match the expected branch/mod set.

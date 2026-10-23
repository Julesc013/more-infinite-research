# MIR 5 API v1 draft SDK

This is developer material for the current MIR API v1 draft. It is not loaded by the player package and is not yet a released compatibility promise. Exact native consumer evidence is linked below; multiplayer, optional-absence and final-candidate API qualification remain separate.

The annotation-only [Lua surface](api-v1.lua) follows the implemented data module `__more-infinite-research__.api.v1.data` and the runtime remote interface `more-infinite-research.api.v1`. It has no implementation code, registration, storage, or callbacks.

## Canonical consumer examples

Use the existing independent fixtures as the examples. They are deliberately separate Factorio mods and are not copied into this SDK.

- [api-alpha](../../tests/mir5/fixtures/api-alpha/data.lua) is the required consumer. Its [dependency metadata](../../tests/mir5/fixtures/api-alpha/info.json) requires MIR, its data-stage module call creates a local forward-reference family, and its [runtime consumer](../../tests/mir5/fixtures/api-alpha/control.lua) queries the public remote interface.
- [api-beta](../../tests/mir5/fixtures/api-beta/data-final-fixes.lua) is the optional, late data-stage consumer. Its [dependency metadata](../../tests/mir5/fixtures/api-beta/info.json) makes MIR optional, its `data-final-fixes.lua` checks `mods["more-infinite-research"]` before importing, and its [runtime consumer](../../tests/mir5/fixtures/api-beta/control.lua) checks `script.active_mods["more-infinite-research"]` before calling the remote interface.

`mods` is a settings/data-stage global. It is unavailable to runtime code. Runtime consumers must use `script.active_mods`, call the remote interface only when game state is available, and must not query it from `on_load`.

## Current data surface

`get_version()` returns the API version and selected product distribution, for example `{major = 1, minor = 0, product = "5.0.20000"}` on F200. `get_capabilities()` reports the selected engine adapter: modern targets support `technology_creation`, `technology_family`, and `recipe_productivity`; data-stage `research_query` is false. Check capabilities before requesting an effect unavailable on a historical engine. The data module provides `add_technology`, `add_technologies`, and `add_productivity`.

A data call operates immediately in the caller's present data stage through native publication. It does not enqueue a contribution for an MIR finalizer. A required consumer declares the normal MIR dependency and may import directly. An optional consumer declares `? more-infinite-research >= 5.0.21000`, guards with `mods[...]` before its import, and makes its absent-MIR path inert.

The current boundary accepts a nonempty dense technology family of at most 64 tables, or at most 64 distinct recipe names for `add_productivity`. It accepts plain values only: no metatables or cycles, finite numbers, and strings no longer than 4096 bytes. The family copy shares a 512 key/value-entry budget and a maximum table nesting depth of 16. Native prototype fields stay native and Factorio remains the final schema validator. A rejected data call raises `MIR_API:<code>: <detail>` with one of `invalid_definition`, `duplicate_identity`, `missing_target`, or `unsupported_capability`; it does not return a pending request.

## Current runtime surface

Control registers `get_version`, `get_capabilities`, and `get_research` under `more-infinite-research.api.v1`. The runtime API is read-only. `get_research(force_index, technology_name)` returns a detached snapshot or `nil, error_code`; current error codes are `invalid_force`, `invalid_technology`, `game_unavailable`, `force_not_found`, `technology_not_found`, and `unsupported_capability`.

The snapshot exposes native `name`, `force_index`, `researched`, `level`, `enabled`, optional `saved_progress`, and `max_level`. On the current Factorio 2.1.23 target these numeric fields are finite native values. Infinite technology maximum is the native `4294967295` value, not a synthesized data-stage `"infinite"` string. `level` is the native current level, not a derived completed-level total.

## Draft target and validation limits

The canonical fixtures use Factorio 2.1 metadata (`base >= 2.1.23`); each `info-f200.json` supplies the exact Factorio 2.0.77 variant while sharing the same Lua consumer. [The F200 selection](../../tests/mir5/profiles/api-consumers-f200-2077.json) runs required alpha, optional late beta and the physical-production observer together. [Exact native evidence](../../spec/mir5/evidence/api-consumers-f200-chain.json) at source `86a9babd4462b5967f56bcc57669c22de26474fb` proves immediate data publication, independent detached runtime queries, alpha’s native crafting bonus, 200 then 202 cables from equal 100-plate inputs, save and two cold reloads. Research in that scenario uses native setters, not labs. Optional absence, joining clients, other modpacks, historical consumer targets and final released API acceptance remain separate. Use disposable test worlds while the product is incomplete.

Run the current host controls with the explicit private Lua 5.2 runtime input:

```powershell
python -B tests/mir5/test_api.py --lua-runtime-dir build/tmp/mir421-lua-runtime
python -B tests/mir5/test_runtime_api.py --lua-runtime-dir build/tmp/mir421-lua-runtime
python -B tests/mir5/test_sdk.py --lua-runtime-dir build/tmp/mir421-lua-runtime
```

`test_sdk.py` is a Lua host control that executes these small examples against the implemented data and runtime modules. It does not replace the independent consumer fixtures or establish Factorio-native qualification.

## Published MIR 4 transition boundary

The pinned MIR 4.7 F210 player archive shipped two conditional, unversioned runtime interfaces. `more-infinite-research-settings` was gated by `settings_profiles` and exposed `export_string(options)` and `validate_string(text)`: only strict `options.compact == true` changed export, a successful export returned an encoded string, failures returned `nil, error`, and validation returned either `{valid = true, recognized, invalid, unknown, import_setting}` or `{valid = false, error}`. `more-infinite-research-browser` was gated by `research_library` and exposed `open(player_index, options)`, whose recognized options were `mode` (1, 2, or 3), `search`, `tab` (`settings`, `research`, `queue`, `availability`, or `help`), `settings_scope` (`research` or `options`), `status` (1 through 4), `family`, `sort`, `selected`, `hidden`, and `page` (through the then-current catalogue limit); it returned whether the target player's browser root was open after rendering.

## Current source bridge and remaining transition work

Current MIR 5 control source collision-checks and registers both historical names, but this is a source and host-control bridge, not native or compatibility qualification. The settings facade retains the two method names, strict compact test, effective registered-setting export, metadata fields `mir_version`, `factorio_version`, and `import_setting`, and the validation count/result shape. It exports only the current MIR 5 registered settings through the MIRSET1 codec; it does not recreate the historical setting catalogue or apply a decoded profile.

The browser bridge maps historical `search` to the current `query` and accepts `family`, `status`, `sort`, `selected`, `hidden`, and integral `page` from 1 through 30000. It verifies a selected technology against the player's native force before passing it to the Library and retains the boolean open result. The current bridge also accepts `mode`, `tab`, `settings_scope`, `settings_search` and `visibility`; Library host controls cover their current mapping. Rendered joined-client behavior still requires native qualification. The bridged `page` is a saved continuous UI position, and neither historical nor current `open` supplies a remote row/page response envelope; pagination equivalence has not been established.

No identified independent old consumer exists within the pinned source and archive search scope. The required and optional `examples/` trees are current MIR 5 public usage examples, not evidence of a previous consumer. MIR4 API-preview response fields and MEP envelope fields are developer-only historical preview shapes: MIR 5 neither emits nor imports them. The normative V0 removal obligation remains open and still requires accepted independent-consumer migration evidence plus an explicit later-release decision; this bridge does not satisfy or amend either gate.

Read the [normative API contract](../../spec/mir5/api.md) for lifecycle and future-extension rules. The alpha and beta fixtures above remain the canonical current conformance consumers.

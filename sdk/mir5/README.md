# MIR 5 API v1 draft SDK

This is developer material for the current MIR API v1 draft. It is not loaded by the player package, it is not a released compatibility promise, and it establishes no native, save/reload, multiplayer, modpack, or API-stability qualification.

The annotation-only [Lua surface](api-v1.lua) follows the implemented data module `__more-infinite-research__.api.v1.data` and the runtime remote interface `more-infinite-research.api.v1`. It has no implementation code, registration, storage, or callbacks.

## Canonical consumer examples

Use the existing independent fixtures as the examples. They are deliberately separate Factorio mods and are not copied into this SDK.

- [api-alpha](../../tests/mir5/fixtures/api-alpha/data.lua) is the required consumer. Its [dependency metadata](../../tests/mir5/fixtures/api-alpha/info.json) requires MIR, its data-stage module call creates a local forward-reference family, and its [runtime consumer](../../tests/mir5/fixtures/api-alpha/control.lua) queries the public remote interface.
- [api-beta](../../tests/mir5/fixtures/api-beta/data-final-fixes.lua) is the optional, late data-stage consumer. Its [dependency metadata](../../tests/mir5/fixtures/api-beta/info.json) makes MIR optional, its `data-final-fixes.lua` checks `mods["more-infinite-research"]` before importing, and its [runtime consumer](../../tests/mir5/fixtures/api-beta/control.lua) checks `script.active_mods["more-infinite-research"]` before calling the remote interface.

`mods` is a settings/data-stage global. It is unavailable to runtime code. Runtime consumers must use `script.active_mods`, call the remote interface only when game state is available, and must not query it from `on_load`.

## Current data surface

`get_version()` returns `{major = 1, minor = 0, product = "5.0.21000"}`. `get_capabilities()` reports `technology_creation`, `technology_family`, and `recipe_productivity` as true, and `research_query` as false. The data module provides `add_technology`, `add_technologies`, and `add_productivity`.

A data call operates immediately in the caller's present data stage through native publication. It does not enqueue a contribution for an MIR finalizer. A required consumer declares the normal MIR dependency and may import directly. An optional consumer declares `? more-infinite-research >= 5.0.21000`, guards with `mods[...]` before its import, and makes its absent-MIR path inert.

The current boundary accepts a nonempty dense technology family of at most 64 tables, or at most 64 distinct recipe names for `add_productivity`. It accepts plain values only: no metatables or cycles, finite numbers, and strings no longer than 4096 bytes. The family copy shares a 512 key/value-entry budget and a maximum table nesting depth of 16. Native prototype fields stay native and Factorio remains the final schema validator. A rejected data call raises `MIR_API:<code>: <detail>` with one of `invalid_definition`, `duplicate_identity`, `missing_target`, or `unsupported_capability`; it does not return a pending request.

## Current runtime surface

Control registers `get_version`, `get_capabilities`, and `get_research` under `more-infinite-research.api.v1`. The runtime API is read-only. `get_research(force_index, technology_name)` returns a detached snapshot or `nil, error_code`; current error codes are `invalid_force`, `invalid_technology`, `game_unavailable`, `force_not_found`, `technology_not_found`, and `unsupported_capability`.

The snapshot exposes native `name`, `force_index`, `researched`, `level`, `enabled`, optional `saved_progress`, and `max_level`. On the current Factorio 2.1.23 target these numeric fields are finite native values. Infinite technology maximum is the native `4294967295` value, not a synthesized data-stage `"infinite"` string. `level` is the native current level, not a derived completed-level total.

## Draft target and validation limits

This draft is scoped only to the current Factorio 2.1 path; the two consumer fixtures declare `base >= 2.1.23`. It has host controls for the data and runtime boundary. Native consumer, optional-absence, save/reload, joining-client, cross-modpack, historical-target, and stable API acceptance remain separate qualification work. Use a disposable test world only.

Run the current host controls with the explicit private Lua 5.2 runtime input:

```powershell
python -B tests/mir5/test_api.py --lua-runtime-dir build/tmp/mir421-lua-runtime
python -B tests/mir5/test_runtime_api.py --lua-runtime-dir build/tmp/mir421-lua-runtime
```

## Legacy consumer audit remains open

The required and optional `examples/` trees are retained minimal public usage examples. They are not an audit of a real previous consumer. No MIR 4/MEP real-consumer inventory, preserved-field record, converter, adapter, or documented major-version transition has been implemented here. In particular, this draft does not reinterpret `MIR4ApiResponseV1` or historical MEP discovery data as MIR 5 input. Complete that audit before retiring an externally consumed old contract.

Read the [normative API contract](../../spec/mir5/api.md) for lifecycle and future-extension rules. The alpha and beta fixtures above remain the canonical current conformance consumers.

---
title: "Finite8 isolated input refusals and cap boundaries"
status: prepared-not-executed
applies_to: "Factorio 2.1.23 Base"
audience: developer
doc_type: test-fixture
owner: mir-maintainers
last_reviewed: 2026-11-07
---

# Separate observer0.2 controls

These are new prepared native controls; none has been executed by this preparation. The original observer0.1.0 directory, profiles and archive pins remain unchanged and reachable through [the original handoff](README.md) and source446ec20. Its passed source save7019 and actual published capture3CEC are evidence for their original exact inputs, not interchangeable observer0.2 saves.

Build a NEW published source with observer0.2.0 and retain that identical observer archive through every first-entry/control arm; adding or changing an observer on the first MIR4→MIR5 entry would itself violate the safety guard.

| Stage/profile suffix | Input | Isolated change | Required outcome |
|---|---|---|---|
| `boundary-source-f210` | Fresh published4.7.21003, Defaults, provider0.1.0 | Observer0.2.0 installed from creation | Actual MIR8 lab completion, paid bonus+.6, next9, current42%/queue automation, paused27%, disabled foreign7, save and two cold reloads; independently capture actual MIR-context transported row before any first entry |
| `boundary-current-f210` | Protected NEW0.2 source save | MIR only to exact13f6cc8 /5.0.21007 | Preserve all source witnesses, save/two reloads, and independently observe actual MIR-context `storage.mir_finite_research_speed` schema1/technology8/predecessor7/provider identity before the cap stage |
| `boundary-provider-refusal-f210` | Copy of that NEW published0.2 source save | Provider0.1.0→0.1.1 only | Exact MIR safety refusal and governed nonzero natural exit; original save unchanged; no successor |
| `boundary-settings-refusal-f210` | Another copy of that same NEW published0.2 source save | Cap0→8 only using pinned File settings | Exact MIR safety refusal and governed nonzero natural exit; original save unchanged; no successor |
| `boundary-cap8-f210` | Protected accepted current0.2 save with actual current marker | Cap0→8 only using the same pinned File settings | Earned8/bonus preserved; MIR8 next9 disabled and visible, removed from queue,42% retained on its native `saved_progress`; automation current at0%; paused8/27% and all foreign7 state unchanged; save and two cold reloads |
| Reuse `boundary-current-f210` | Protected completed cap8 save | Restore Defaults/cap0 | Release MIR-owned8 enablement and its earlier visibility value; retain42% native detached work and automation queue/current; do not reconstruct cancelled MIR8 queue intent; save and two cold reloads |

The full filenames begin `tests/profiles/native-research-speed-finite-`. The observer independently enforces phases and the effective cap before saving; it never reads another mod's storage, seeds a legacy row, modifies target technology costs, or repairs cap results.

The positive-cap oracle follows SET-03 and RUN-02 plus the established absolute-cap queue contract in `tests/test_caps.py` and the finite8 ownership boundary in `tests/test_continuation_ownership.py`. The42% detached-work expectation is a preservation requirement, not a candidate-derived observation; a native disagreement must remain an adverse result. No additional laboratory completion is claimed for the cap/uncap stages.

Provider0.1.1 changes only its metadata version and keeps the original596-byte finite7 Lua blob9888359 exactly; observer0.2 permits both named provider versions so a dependency/fixture rejection cannot substitute for the MIR refusal.

## Settings input

`control-settings/published-startup.json` retains all889 startup values from actual published capture SHA256 `3CEC4CBED1709CF2543BB1C0B5E8AF009A7C0BDCA324F6469AECEEDB609FE539`; the888-key current diagnostic export is a different context. `cap8-settings.dat` changes only `mir-max-level-research-speed` from0 to8 and uses the exact2.1.23 property-tree header.

The settings binary SHA256 is `3018731C6C24960C3664330755C5D435010788BE6186265B6EEDEF2275BFE0E9` (58757 bytes). Its provenance records the actual source row/map and the historical writer's exact hash; only that writer's pure `text`/`tree` codec functions are reused. The original writer CLI is not invoked and is not asserted to support F210.

`control-settings/write-cap8.py` reproduces the binary from the hash-pinned map into a NEW output file. The focused test decodes the binary independently, checks its header and all889 values, and permits only the one requested delta. The native owner must still confirm the pinned engine reads effective cap8 and the intended unchanged settings; host decoding alone is not native acceptance.

The optional runner seam accepts File settings only for this named modern F210 input-save case, with explicit path/hash, matching profile mode/hash and exact2.1.23 header. Defaults and historical activation paths retain their previous argument selection. For the positive cap stage, add these arguments to the existing governed runner invocation:

```powershell
SettingsPath = 'tests/fixtures/native-research-speed-finite/control-settings/cap8-settings.dat'
SettingsSha256 = '3018731C6C24960C3664330755C5D435010788BE6186265B6EEDEF2275BFE0E9'
```

## Native execution custody

The native owner supplies new source/current/capped save paths and their actual protected SHA256 values; none exists for observer0.2 at preparation time. Every full positive arm uses `CaseName='native-research-speed-finite'`, its exact selected profile, the unchanged active-mod observer0.1.0, exact fixture projections, and the existing `Invoke-NativeFixture.ps1` driver with explicit `InputSavePath`/`ExpectedInputSaveSha256` for each transition.

Expected-negative arms use the existing governed lower helper's nonzero-exit receipt and the exact profile's `expected_native_error` string: `MIR cannot safely change finite research-speed ownership on this existing save; restore the previous mod selection and original save`. Require that actual native error, nonzero natural exit, correct selected archive/settings inputs and unchanged protected source; dependency failure, observer assertion, timeout, a missing input or mere process termination is adverse. Do not weaken the full fixture driver's fatal-diagnostic checks or count a saved successor for either refusal.

Use only fresh checkout-local projections from the frozen raw Git blobs: `cap-controls/` contains exactly its five package members, `provider-changed/` its two members, and the original provider/active observer retain their existing bytes. Package through `tools/package.py`; compare every profile pin before native admission. Keep control inputs, settings codec, provenance and this guide outside all fixture/player ZIPs.

The new observer archive SHA256 is `BB233B2AB7B5D297B6EB0600A6099871AF0C59F20F8E62DF3C96FEDE846BA8DA` (5812 bytes); provider0.1.1 is `454DF42BEA178B7E8DA897398E8116C491A13DCD604C59647004B2C6699FB7E5` (931 bytes). No native process, direct-library install/activation or release operation belongs to this preparation.

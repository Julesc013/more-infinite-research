---
title: "Finite foreign research-speed7 to MIR8 native preparation"
status: prepared-not-executed
applies_to: "Factorio 2.1.23 Base"
audience: developer
doc_type: test-fixture
owner: mir-maintainers
last_reviewed: 2026-11-07
---

# Finite foreign7 to MIR8

This is one prepared F210 source/upgrade/reload scenario, plus a separate fresh-current arm; no native run, source save, transported ledger observation, cap rendering or Library result is asserted.

The independent source is published `v4.7.3` commit `8643cc91bc915e008556a5315dbb0a743247e7ab`, archive `more-infinite-research_4.7.21003.zip` SHA256 `B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852` (1463293 bytes).
The provider retains its original identity/version and exact Lua blob `9888359ab72cdc95fd10192b0e691254d31c2865` from `fixtures/finite-base-extension-level/data-final-fixes.lua`; it copies actual Base6 and declares finite7 with count777, time77, red science and prerequisite6.
The published planner `db03d9f58901c9c49ce4f3dd996833bfc774105b`, builder `370f11f586fd200c1eed3ba3407f63d14aacdf65`, binding `439a3266279dcae287337b2516cf0303d49ddb16` and controller `48de6bdf4332939c73ec9fc4ae793a9623c015da` identify the independent MIR8 construction and transported-v3 producer path; their existence does not prove that a particular save contains a valid row.
Recovered defaults are formula `1025.15625*1.5^(L-8)`, time120, copied laboratory-speed .6, six packs in automation/logistic/chemical/production/military/utility order, and prerequisite6/7 followed by those six same-name science gates.
The original independent source/science and published-producer reviews remain in private `origin/review/aero-native-family-host-controls-r01` (`5ed804c`), under `projects/mir/runs/aero-finite-research-speed-source-inputs-r01/old-science.json` and `projects/mir/runs/aero-settings-and-discussion-audit-r01/finite8-published-producers.json`; they are references, not repository execution dependencies.

The observer validates those exact technology fields before adding its own accelerated lab; it never changes foreign7 or MIR8.
Only the fixed eight prerequisites are seeded; MIR8 itself earns one actual laboratory completion and a measured native bonus increase of .6.
The lab then freezes, MIR8 remains at next level9 with current research42% and a second `automation` queue entry, a separate paused force keeps27% work, and foreign7 is independently disabled.
The successor and reload checks preserve levels, flags, bonus, queue order, current work, paused work and native creator histories.
This is a disposable native-effect/save scenario, not full factory acquisition or normal-speed/performance qualification.

Use the same provider0.1.0, observer0.1.0 and generic active-mod observer0.1.0 ZIP bytes in every arm.
Do not change a fixture version, add an observer, or change settings on first MIR4→MIR5 entry: the one-time legacy guard requires all nonMIR mod selections/versions and startup settings to remain unchanged.
The two profiles differ only in MIR version/archive and their explanatory scope.
The candidate pin is exact `13f6cc857c26d198df1c275106dcb7d0334ef748` source, ZIP SHA256 `81C896F0F33CE7CFF1E8ED78AA7F8F4014A97123DFD6DACFC492247625775776`; the source version remains5.0.7 and no public release is changed.
The engine pin is the inspected standalone `D:/Games/Factorio/2.1/bin/x64/factorio.exe`, SHA256 `8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38`, version2.1.23; a different executable with the same version needs its own reviewed input pin.

## Preparation and execution handoff

1. Inspect `tests/Test-MIR5HostControls.ps1 -Plan`, run development health, and obtain the sole native assignment; use the existing governor and direct `D:/Projects/Factorio/testmods/2.1` library, restore its controls and preserve all outcomes.
2. Freeze the fixture commit and create three checkout-local source projections from its raw Git blobs: `provider/`, `observer/`, and the existing `tests/fixtures/active-mods-observer/` (exactly its selected two members).
3. Use `tools/package.py --source <projection> --output <new-checkout-local-zip> --record <new-record>` for each projection; compare with every profile archive pin before placing the exact archives into the exclusively owned direct library.
4. Build the candidate with `python -B tools/package.py --source source --target f210 --revision 13f6cc857c26d198df1c275106dcb7d0334ef748 --output <new-candidate-zip> --record <new-record>` and verify its pinned bytes; the published archive must be the actual hash-verified release asset, never a reconstruction.
5. Invoke the existing runner below for the published profile; retain its completed save unchanged and record the actual source save SHA256.
6. Before first successor admission, use the existing governed RCON controller's MIR-context execution to run the read-only `observe-published.lua` body against a copy of that exact source save, preserving its output and controller/save provenance; do not run it in the observer mod's context, which has separate storage.
7. Independently inspect the actual managed8 row: policy3, source `base-continuation`, operation `emit_base_extension`, setting `mir-max-level-research-speed`, transport/ownership `transported-v3`, legacyfalse, native_finite_stagefalse, no blocked reason, actual `mir32-` fingerprint and finite-positive/infinite selection; missing/adverse data stops admission rather than being repaired or synthesized.
8. Run the current profile with `-InputSavePath <protected-source-save> -ExpectedInputSaveSha256 <actual-source-hash>`; separately run that same current profile without an input save for fresh-current coverage.

```powershell
$finiteArguments = @{
  ArchiveLibrary = 'D:/Projects/Factorio/testmods/2.1'
  FactorioBin = 'D:/Games/Factorio/2.1/bin/x64/factorio.exe'
  ProfilePath = 'tests/profiles/native-research-speed-finite-published-f210.json'
  FixtureSources = @($providerProjection, $observerProjection, $activeModsProjection)
  ExpectedMIRArchiveSha256 = 'B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852'
  ActiveModsObserver = 'mir-fixture-mir5-active-mods-observer'
  CaseName = 'native-research-speed-finite'
  OutputRoot = $newGovernedCheckoutLocalOutput
}
./tools/Invoke-NativeFixture.ps1 @finiteArguments
```

Every full runner arm requires its actual initial result, completed save and two cold reloads; no test double or archive-existence result substitutes.
For successor/fresh, select `tests/profiles/native-research-speed-finite-current-f210.json` and its MIR hash `81C896F0F33CE7CFF1E8ED78AA7F8F4014A97123DFD6DACFC492247625775776`, retaining all three nonMIR fixture sources and archive bytes unchanged.
Changing-provider and changing-settings first-entry native refusals, positive-cap ownership, Library native rendering/input and exports remain separate pending controls; the existing20 ownership host controls cover the relevant strict/rejection paths without native qualification.
The F200 management-only legacy tuple remains insufficient creator proof and is not an accepted native route.

The focused host command is `python -B tests/test_native_research_speed_finite_fixture.py --lua-runtime-dir <pinned-lua52-directory>`; it checks the old provider's original bytes, prototype negatives, source/successor/reloads, fresh-current and loss-of-state opposition with native-shaped doubles.
The module is deliberately standalone in this bounded ownership assignment; adding it to the ordered host driver is an integration change, not a claim that the full driver ran.

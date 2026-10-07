---
title: "Testing And Fixture Strategy"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-10-08
supersedes: []
superseded_by: []
---
# Testing And Fixture Strategy

Updated: 2026-10-08

The release engine runner initializes lease cleanup before imports and admission. An early refusal must preserve its original error instead of failing again because cleanup state is absent. A fresh PowerShell child exercises the actual runner with a missing candidate, checks the original diagnostic and verifies that no run output is allocated; this host-side regression test launches no Factorio process.

The five historical 4.2.1 targets require explicit `-F017Engine` through `-F013Engine` bindings in the release engine runner. Their exact sealed engine hashes and versions remain mandatory; the historical workstation path remains provenance rather than the required current location. Maintenance sealing reads the preserved MIR 3 target/seal identities without requiring those old archives locally, then verifies the actual published `CCC00` predecessor. Non-maintenance sealing still requires its original predecessor archive and engine location. Controlled relocation/missing-archive cases exercise the real readers without claiming native qualification.

Published `CCC00 → CCC01` maintenance execution uses `spec/engines/mir421-native-engine-inputs-v1.json` for the four modern Windows engine identities. The runner and seal consumer share the same exact binary/product/file-version binding. Paths are supplied locally. The F210 input is the observed Steam experimental 2.1.21.87673; F200/F110/F100 retain their exact 2.0.77/1.1.110/1.0.0 inputs. The record includes the observed F210 API/changelog hashes and Steam build, but grants no qualification or publication. It does not update the separate cap-harness admission or transfer older engine evidence. Historical target engine seals remain applicable unchanged.

The frozen v4.1 predecessor and 2.1.20 admission records retain their original bytes and readers. A maintenance seal checks the independently verified published 4.2.0 predecessor and current maintenance engine input; it must not treat the v4.1 archive paths or its 2.1.20 binary as the maintenance predecessor/engine. Existing native execution, source/candidate, save/reload, joined-campaign and release checks remain required. Omitting the maintenance context retains the original engine authority checks.

The release engine runner (`Invoke-MIR42FourTargetEngineRun.ps1`) requires `-LibraryBindingsPath`: a small local JSON object mapping each selected target (`f210` through `f013`) to an absolute flat-library directory. These are local bindings, not tracked workstation requirements. Its modern package workers forward `-LibraryDirectory`, historical fresh loads use the same activation adapter, and upgrade workers receive `-LocalModLibraryDirs`. Required candidate, predecessor and fixture archives must already be installed with the expected bytes; execution neither acquires them nor recreates retired profiles. Package smoke starts with defaults, disables unrelated installed mods, checks the loaded selection and restores prior controls on success or failure. The existing historical receipt retains `staged_candidate_sha256` for its reader contract; it now records the selected library archive's hash and adds `library_input_receipt`, with zero dependency payload copies, links and extractions.

The general validation runner's package smoke scenarios accept `-LibraryDirectory`; unmigrated runtime scenarios stop with `mir-validation-obsolete-runner` before constructing a mod directory. Use the migrated focused progression, upgrade and Library consumers for affected native work. This guard does not disable static checks or scenario listing. Checkout-internal immutable release-custody aliases remain permitted and are not game mod directories. `Test-MIR42NineTargetHistoricalEngineRun.ps1` exercises the actual fresh-load and package-smoke entry points using tiny archives and substituted actors; it is storage/oracle regression evidence, not a nine-engine qualification pass.

The 3.0 compatibility compiler needs tests for both positive emission and negative safety. The goal is not only "the mod loads." The goal is proving that MIR emits, skips, rejects, and reports exactly what the policy says.

Current verification selection uses the declared inputs in `validation/tests.yml`, the existing assurance classes and `.mir/test-impact.yml`. `Test-MIRResearchabilityPlanning.ps1` consumes both `researchability_planning.lua` and `lab_reachability.lua`; its registry input and receipt hashes must include both. `Test-MIRRecipeSourceEpoch.ps1` consumes `recipe_source_epoch.lua`. Both exact acquisition fixtures map to their existing consumers and affected science scenarios. The selector's own known static test has no additional native scenarios. Unowned fixtures and tooling scripts retain conservative coverage. These exact mappings retain the broader static harness policy and grant no native acceptance.

The selection contract itself can be checked without Factorio or dependency archives:

```powershell
.\tests\tooling\Test-MIRDevelopmentCISelection.ps1 -PureSelectionOnly
```

Native lab, emitted research, production, save, multiplayer and engine performance claims still need their selected current-package scenario. Normal serial tests launch directly against the engine-family archive library. Profiles contain only small selection definitions; do not create dependency copies, hard links, extracted mods or replacement modpack directories. Keep compact results and required reproducers after completion; removing an existing archive alias does not reclaim its displayed length while a master link remains.

The existing compatibility runner accepts a `LibraryActivation` for create and reload. `Start-MIRLibraryActivation` validates the profile's exact versions, selected archive hashes and dependency constraints, disables every unselected installed name, and holds selected archives open for reading. It switches only `mod-list.json` and the explicit settings input (or defaults). A durable journal preserves the previous small controls before replacement; the next invocation recovers an interrupted owner before selecting another profile. `Complete-MIRLibraryActivation` restores the previous bytes after all clients exit. The engine's `write-data`, saves and logs remain in the existing approved run directory. Updates and `--sync-mods` are rejected.

`tests/tooling/Test-MIRLibraryActivation.ps1` exercises A/B/A selection, pinned versions, missing/incorrect dependencies, settings isolation, interrupted-owner recovery, exclusive access and the existing create/reload collectors with tiny archives. Its native actor is substituted: these checks do not establish Factorio loading, graphical startup or gameplay. Remaining native consumers still require conversion and selected engine checks; they may not recreate retired profile archives. Two simultaneous clients requiring different active controls need a separately qualified arrangement; they must not silently recreate populated profiles.

The maintainer-authorized profile retirement on 7 October removed all 2,041 archive entries after verifying surviving master file identities and all 473 backup files by SHA-256. The backup replaced the old directory. Definitions and four distinct tiny RIC settings fixtures remain in primary-checkout custody at `build/handoff/MIR421_SOL_CURRENT/profile-retirement-2026-10-07`, with the complete retirement receipt. No dependency archive was copied or linked. The observed free-space delta was -1,126,400 bytes during preservation and removal: displayed alias lengths were not reclaimed physical storage. This custody records old provenance, not current native acceptance or permission to recreate old paths.

The external `testmods` location may be deleted. It is not part of the repository's portable contract: pass an explicit library location containing the required exact releases on each machine. K2 and Tin continuation consumers have no machine-specific library default. Source-only checks need no library. Existing legacy hard-link helpers now reject either endpoint outside their executing checkout before linking or entering copy fallback; they do not make unconverted native runners ready. Only the direct-library path is admitted for normal dependency use.

`Test-MIRF210CurrentBobTinLevel4Continuation.ps1` now uses that direct-library path for both create and reload. Supply one `-LocalModLibraryDirs` entry, `-FactorioBin`, the current `-CandidateZip` and `-SourceMaterializationPath`, and the small exact `-SettingsPath`. Required dependency versions/hashes and the level-three-to-four, +8%, 108-plates-from-100-ore witness remain in the tracked continuation dossier. Install the owned assertion ZIP separately once; its members must match the current fixture. The runner records private initial/final settings and restores the prior controls. Old populated-stage/recovery options refuse before staging; historical V1 results remain under their original source and receipts. The current runner emits V2 results. Without explicit engine arguments it retains the dossier's exact 2.1.20 binding. A fresh observation may supply both `-ExpectedEngineVersion` and `-ExpectedEngineSha256`; the executable and native version report must match, and the original create/production/reload assertions still run. `-SettingsMode Defaults` explicitly starts without inherited settings; file mode still requires the retained settings hash. Results identify the actual engine and settings separately from historical provenance. A new input binding transfers no prior pass. Tiny selector, launch, loaded-selection and reload controls establish the storage conversion, not a new native production pass.

The fresh Bob-only observation on 8 October passed on Factorio 2.1.21 with default settings, source `ffc72dea1f9cfcd012bbe4bcfb7239abbcb0ff37` and F210 archive SHA-256 `8E3028893DDFEB949A1DE316246E29D07BF5C5D242A33E9413A2FF930B3D1A43`. Its result is `build/p/m421-tin-ordering-native-f/9e7b439251694ce5b1fb8bfb0a931ddd/result.json`. The unchanged oracle observed finite levels one through three, continuation level four, a 6% to 8% recipe bonus and 108 plates from 100 ore after reload. Create/reload took 80.04/82.07 seconds. Both used the shared library directly; previous controls were restored, with zero dependency payload copies, links or extraction. This is exact Tin/default-settings evidence, not Bob/Angel combined coverage, a tested cap boundary, F200 acceptance or final release qualification.

That run repaired an upstream-finalizer ordering defect: MIR previously compiled before Bob's Electronics and Technology completed their lab/science changes. F210/F200 metadata now contains hidden optional ordering dependencies for both. A separate late module import also prevented another mod from inspecting the lab acquisition service; the item index now loads in MIR's module scope. The failure-only fixture retains a small post-MIR acquisition observation, including indeterminate trace limits. These observations are not clean compiler replay inputs, and a diagnostic error cannot replace the original Tin assertion failure.

The follow-up at source `aa207cf620535efbfadd12939e0aa3612678ab69`, F210 ZIP SHA-256 `834F1A4730E8711DDBD45581C2723CF7A4D1558341CBF5DC4CB52FC47A74BAAF`, prefers independently acquired machines before exploring their research-gated alternatives. The same engine, Bob releases and default-settings scenario passed in `build/p/m421-machine-native-run-a/9874d197e1b54445b46f1057cab49426/result.json`: level four retained the 8% bonus and produced 108 plates after reload, with controls restored and zero dependency copies, links or extraction. Create/reload took 62.65/66.87 seconds versus the preceding 80.04/82.07 seconds. These are single observations on this host, not a statistical benchmark or broader ecosystem acceptance. Controlled counterfactuals require an initial machine to avoid unrelated technology queries while retaining unavailable, circular, fixed-recipe and necessary research-gate cases; the existing fluid, surface, source-epoch and progression checks remain selected.

The prepared `Test-MIRK2213ImersiteContinuation.ps1` consumer uses direct activation. Supply its current candidate/materialization receipt and the existing V5 engine/dependency observation. The selected library must already contain those exact archives and a fixture ZIP whose members match the current fixture source; input acquisition and fixture construction happen once, separately. Preflight refuses missing versions or stale fixture members. The runner creates only its small selection record and normal run output, preserves the existing level-four/next-level-five, 8% bonus, 42% queued-progress and single-reload oracles, and restores prior library controls. The existing native output budget charges additional active-control and recovery-journal bytes as well as run output; existing archives are not new payload writes. Its V2 result records `library_activation` rather than a fictitious staged-input receipt; older V1 observations retain their original identities. Controlled input tests do not qualify that gameplay outcome on the current package.

The existing manifest-driven `tests/runtime/Test-MIRUpgrade.ps1` also selects predecessor and candidate versions directly in one explicitly supplied library. Both exact MIR archives and the selected assertion fixtures must already be installed there; source-only fixtures are disabled for the candidate phase. The source phase's writable settings are preserved privately and activated for the candidate. Each owned engine invocation verifies the library/configuration and reads back the loaded mod versions; existing source, earned research, reward, save-completion and reload oracles remain required. Result schema 3 records `source_library_activation` and `library_activation`; it does not represent these as hard-link leases.

`tests/runtime/Test-MIRResearchBrowser.ps1` uses the same direct-library path. Supply `-FactorioBin`, `-CandidateZip`, `-LibraryDirectory` and `-Target`; the runner verifies the engine line, current Library modules, installed candidate hash and every assertion-fixture member before activation. It selects only base, MIR and its assertion fixture, establishes default settings, verifies the loaded selection for each create/benchmark/reload, and restores the previous controls. `-PrepareInputsOnly` constructs the small owned fixture ZIP inside the checkout without requiring an engine, candidate or library and without native execution. Install that prepared fixture separately once. Runtime receipts record `library_activation`, not an immutable-input lease. The existing `-Graphics` player, localization, GUI and save/reload assertions remain required for those claims; host adapter controls establish no graphical or gameplay pass.

For optional-artwork acceptance, select `-DlcIconCase Defaults`, `RawOptIn`, `ImportedOptIn` or `RawOptInImportedOff` consistently during fixture preparation and execution. The fixture first verifies the production checkbox remains default-off, then sets only the requested test defaults and an actual MIRSET1 import where selected. Native creation writes the binary settings subsequently read by graphical startup and reload; the receipt retains a private hash-verified settings snapshot. Post-MIR assertions verify raw/imported precedence, both shortcut sizes and absence of Space Age/Elevated Rails resource paths throughout final technologies and shortcuts. Each engine invocation must produce exactly one matching observation. This extends the existing base-only selection, not the installed engine: a run with DLC installed but disabled does not establish physical-absence qualification. The default `None` keeps ordinary browser acceptance unchanged.

The personal-state lifecycle runner now accepts explicit `-LibraryDirectory` and `-FactorioExe` inputs and selects archives directly. Use `-Operation PrepareInputs` with the selected target, input mode and candidate to prepare its small owned fixture ZIPs separately; this mode performs no Factorio execution or library activation. Install those exact fixtures once, then use the default `Run` operation. Each phase binds the installed candidate bytes and every fixture member, establishes defaults initially, carries a private settings snapshot forward, and restores prior library controls after all owned processes exit. Removal disables MIR in the active selection while retaining its archive. Current V2 governed results contain `library_input_receipts`; historical lease receipts retain their original identities.

Within one lifecycle phase, the owned server and clients use the same fixed mod-list and settings. Additional client admission verifies every live engine is a still-owned direct child, checks the selected engine and configuration, and reads the selection without rewriting it. An unrelated engine, reused process identity or changed selection is refused. All three logs must match the selected mods and versions. This host-side arrangement still needs current native two-client acceptance; it supplies no physical-input or multiplayer pass by itself.

The shared native-probe driver explicitly waits for its native child and propagates that child's exit code. PowerShell's call operator returned early for the Windows GUI executable during the first direct browser attempt, leaving only Factorio's startup header before the governor stopped the owned tree. The loaded-selection check rejected that attempt. A tiny delayed Windows GUI executable reproduces the premature return with the old driver and completes with the explicit wait; the controlled resource suite retains that regression alongside argument, environment and output-budget checks. Engine loads and graphical assertions remain separate native evidence.

The browser failure receipt preserves the original engine/resource error separately from control-restoration status. If the engine has not fully exited, restoration remains refused and the durable library journal stays available for recovery. That cleanup refusal must not replace the primary exception. Tiny-file controls execute the runner's actual catch block for successful cleanup, delayed-shutdown refusal and exhausted receipt budget; they launch no engine.

The browser fixture observes the base recipe schema to select F210 `categories` or F200 `category`. Its native discovery witness waits for two unchanged client-display observations before opening the Library: graphical startup applies the window resolution and scale after the save's first tick. The original root, search and filter must then remain intact throughout discovery. Twenty-six controlled opposing cases cover startup, later invalidation, disconnects, deadlines and translation completion. This setup correction changes no player UI behavior and does not waive widget-preservation assertions.

Use the same upgrade command with `-PrepareInputsOnly` to generate the small specialized MIR-owned assertion ZIPs inside its approved build root. The preparation receipt lists their exact identities and any selected SIF dependencies, and explicitly says `prepared-not-native-tested`. This mode starts no engine and writes no archive library. It has its own small-output capacity check; normal execution retains the native reserve and declared memory budget. Supplying a construction manifest still requires the existing clean-source check. Acquire or install only these selected inputs separately, then run without `-PrepareInputsOnly` and supply `-LocalModLibraryDirs`. Neither step reconstructs historical populated profiles.

The first direct-library SIF native attempts exposed two input/fixture failures, before candidate acceptance: Factorio 2.1.21 rejects the removed `fuel_category` field in Space Is Fake 1.0.76, and the F200 base-only fixture selected `mining-productivity-4` although enabled Space Age removes it. The F210 scenario now pins upstream Space Is Fake 1.0.78 with cr-commons 1.0.33; those exact acquired bytes require fresh execution. The SIF specialization uses Space Age's infinite `mining-productivity-3` for the F200 level/queue check, preserving level 5 and 37% progress. Ordinary base-only fixture input is unchanged. These corrections do not turn either failed attempt into a pass.

When the hosted `static.mir4-platform-preview` worker fails on a stale generated projection, the same worker can preserve a separate SDK generation repair artifact. It invokes the existing complete fixed-point writer from the exact clean checkout and exports only changed files returned by that writer, with paths, hashes, source commit/tree, player-source fingerprint and run identity. The output is limited to 16 MiB; no player package or dependency archive is constructed. The original test and verification gate remain failed. Before adopting these bytes locally, verify the producer and exact source, all file hashes and generated path scope; preserve any local changes. Commit the generated corrections and obtain fresh required checks before integration. This artifact provides generated source for repair; it grants no native, release or signing acceptance.

## Test Pyramid

### Static Tests

- schema validation;
- stable sort helpers;
- stable ID generation;
- architecture import-direction linting;
- policy linter;
- claim linter;
- manifest linter;
- `DecisionRecord` validator;
- `StreamSpec` validator;
- settings parser;
- package hygiene;
- no forbidden runtime tick handlers.

### Synthetic Runtime Fixtures

- base recipe productivity;
- self-loop recipe;
- barrel/container return loop;
- filter cleaning loop;
- catalyst return loop;
- voiding sink;
- recycling recipe;
- matter/transmutation loop;
- hidden valid-looking recipe;
- recipe with `maximum_productivity = 0`;
- external owner exact match;
- external owner value mismatch;
- lab with no compatible science packs;
- science dependency cycle;
- loader-like item that is not a loader;
- mining-drill-like item that is not a mining drill;
- machine with base productivity;
- beacon/recycler/module rule-surface observer.

### Real Mod Fixtures

- base;
- Space Age;
- Air Scrubbing;
- ATAN Ash;
- ATAN Nuclear Science;
- AAI Loaders;
- AAI Industry;
- Big Mining Drill;
- Fluid Must Flow;
- Robot Attrition;
- Jetpack;
- Equipment Gantry;
- Krastorio 2;
- Krastorio 2 Spaced Out;
- Bob's focused material subsets;
- Angel/Bob material signal fixture;
- Space Exploration lane;
- Py-style material-family smoke fixture.

## Golden Outputs

Each fixture should assert:

- facts exported;
- candidates discovered;
- classifications stable;
- decisions stable;
- generated streams match expected;
- rejected recipes match expected;
- unknown candidates bounded;
- science packs researchable;
- labs compatible;
- no duplicate owners;
- no unexpected prototype mutations;
- package hygiene preserved.

## Report Diffing

Use report diffing when a mod updates or a classifier changes:

```powershell
.\tools\commands\planner\Compare-MIRPlannerReports.ps1 `
  -Before build\previous\mir-planner `
  -After build\current\mir-planner
```

The diff should summarize:

- new generated streams;
- removed generated streams;
- target recipe changes;
- new unknown candidates;
- resolved unknown candidates;
- new loop risks;
- new owner conflicts;
- new lab/science incompatibilities;
- cap changes;
- claim-level changes;
- package content changes.

## Release Gate

For 3.0 release candidates, require:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin '<Factorio 2.1 binary>'
.\tools\mir.ps1 release gate --profile release-targeted-2.1 --no-git-pull
git diff --check
```

Any generated report changes must be explained by source changes or restored if they are only local run churn.

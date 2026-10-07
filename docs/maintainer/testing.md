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

The external `testmods` location may be deleted. It is not part of the repository's portable contract: pass an explicit library location containing the required exact releases on each machine. K2's direct consumer has no machine-specific library default. Source-only checks need no library. Existing legacy hard-link helpers now reject either endpoint outside their executing checkout before linking or entering copy fallback; they do not make unconverted native runners ready. Only the direct-library path is admitted for normal dependency use.

The prepared `Test-MIRK2213ImersiteContinuation.ps1` consumer uses direct activation. Supply its current candidate/materialization receipt and the existing V5 engine/dependency observation. The selected library must already contain those exact archives and a fixture ZIP whose members match the current fixture source; input acquisition and fixture construction happen once, separately. Preflight refuses missing versions or stale fixture members. The runner creates only its small selection record and normal run output, preserves the existing level-four/next-level-five, 8% bonus, 42% queued-progress and single-reload oracles, and restores prior library controls. The existing native output budget charges additional active-control and recovery-journal bytes as well as run output; existing archives are not new payload writes. Its V2 result records `library_activation` rather than a fictitious staged-input receipt; older V1 observations retain their original identities. Controlled input tests do not qualify that gameplay outcome on the current package.

The existing manifest-driven `tests/runtime/Test-MIRUpgrade.ps1` also selects predecessor and candidate versions directly in one explicitly supplied library. Both exact MIR archives and the selected assertion fixtures must already be installed there; source-only fixtures are disabled for the candidate phase. The source phase's writable settings are preserved privately and activated for the candidate. Each owned engine invocation verifies the library/configuration and reads back the loaded mod versions; existing source, earned research, reward, save-completion and reload oracles remain required. Result schema 3 records `source_library_activation` and `library_activation`; it does not represent these as hard-link leases.

`tests/runtime/Test-MIRResearchBrowser.ps1` uses the same direct-library path. Supply `-FactorioBin`, `-CandidateZip`, `-LibraryDirectory` and `-Target`; the runner verifies the engine line, current Library modules, installed candidate hash and every assertion-fixture member before activation. It selects only base, MIR and its assertion fixture, establishes default settings, verifies the loaded selection for each create/benchmark/reload, and restores the previous controls. `-PrepareInputsOnly` constructs the small owned fixture ZIP inside the checkout without requiring an engine, candidate or library and without native execution. Install that prepared fixture separately once. Runtime receipts record `library_activation`, not an immutable-input lease. The existing `-Graphics` player, localization, GUI and save/reload assertions remain required for those claims; host adapter controls establish no graphical or gameplay pass.

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

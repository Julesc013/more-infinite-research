---
title: "Testing And Fixture Strategy"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-10-09
supersedes: []
superseded_by: []
---
# Testing And Fixture Strategy

Updated: 2026-10-09

The historical target adapter declares `player` as the handcrafting prototype for 0.13–0.16; 0.17 and newer retain `character`. The shared acquisition solver uses that declaration when proving a laboratory's placement-item route, retains category checks and rejects fluid handcrafting. Controlled lab/researchability cases cover both prototype names, mismatched adapters, missing categories, fluid coproducts and unchanged input prototypes. These controls do not establish historical native catalogue or save acceptance.

The same historical adapter maps MIR's built-in science choices to native names. Factorio 0.15/0.16 uses `science-pack-1`, `science-pack-2`, `science-pack-3` and `high-tech-science-pack`. Factorio 0.13/0.14 retains the terminal predecessor's alien-science mapping for later roles, with one deduplicated official progression. The shared registry, default selector and MIR-owned direct-effect declarations use the mapping before compatibility patches; explicit ecosystem ingredients retain their identities. The native fixture expects alien science for character upgrades on 0.13/0.14 and high-tech plus military science on 0.15/0.16. It also checks research and actual crafting reward; a nonempty ingredient list alone is insufficient.

Factorio 0.13/0.14 also requires a singular technology `icon`. Its adapter declares that capability; presentation projects the selected base asset into the native field before the compiler creates the immutable technology design. Layered targets retain all layers and tint. Controlled tests cover both shapes and source immutability; the native fixture checks the actual emitted field before the engine validates the prototype.

The 0.13/0.14 adapter excludes the unsupported `worker-robot-battery` modifier and its research stream. Native 0.14 validation exposed the invalid capability after the science and icon corrections restored emission. The existing target filter consumes the corrected effect list; no substitute reward is emitted. The native fixture also requires that unsupported technology to remain absent.

The current nine-target F015 and F016 ZIPs passed the existing historical handcrafting fixture on 8 October at harness source `0b1a1e38c26fd4f38203031e3f9700b988785589`. Exact engines 0.15.40 and 0.16.51 each observed five available character research streams, their native high-tech/military science, valid prerequisites and icon layers, and an actual crafting-speed reward from zero to 5%. Results are `build/p/m421-current-historical-native-f015-a/result.json` (SHA-256 `817418462671F9A51B5264A1F759496FD2FF2AAE375314005845EE8C0E86BD2F`) and `build/p/m421-current-historical-native-f016-a/result.json` (`DFD0E6C147ADDC3D586FAB9F6E3EAD0E264BC5EDBD824BFB22595D905B7C7D53`). Candidate hashes are `DBA338C0EB671739F2EBFD91BBED359789224CB641FC075CBB57DE37AE7721A1` and `83259DB03C65CE31A26237E92108C199A211FFAFE128D833B62546ECCFA2E9D2`. Both used their configured flat libraries, restored controls and created no dependency copies or archive links. These are fresh base/default results, not published-predecessor upgrades or reload acceptance.

The release engine runner initializes lease cleanup before imports and admission. An early refusal must preserve its original error instead of failing again because cleanup state is absent. A fresh PowerShell child exercises the actual runner with a missing candidate, checks the original diagnostic and verifies that no run output is allocated; this host-side regression test launches no Factorio process.

The five historical 4.2.1 targets require explicit `-F017Engine` through `-F013Engine` bindings in the release engine runner. Their exact sealed engine hashes and versions remain mandatory; the historical workstation path remains provenance rather than the required current location. Maintenance sealing reads the preserved MIR 3 target/seal identities without requiring those old archives locally, then verifies the actual published `CCC00` predecessor. Non-maintenance sealing still requires its original predecessor archive and engine location. Controlled relocation/missing-archive cases exercise the real readers without claiming native qualification.

Published `CCC00 → CCC01` maintenance execution uses `spec/engines/mir421-native-engine-inputs-v1.json` for the four modern Windows engine identities. The runner and seal consumer share the same exact binary/product/file-version binding. Paths are supplied locally. The F210 input is the observed Steam experimental 2.1.21.87673; F200/F110/F100 retain their exact 2.0.77/1.1.110/1.0.0 inputs. The record includes the observed F210 API/changelog hashes and Steam build, but grants no qualification or publication. It does not update the separate cap-harness admission or transfer older engine evidence. Historical target engine seals remain applicable unchanged.

The frozen v4.1 predecessor and historical 2.1.20 admission records retain their original bytes at their pinned sources. A maintenance seal checks the independently verified published 4.2.0 predecessor and current maintenance engine input; it must not treat the v4.1 archive paths or its 2.1.20 binary as the maintenance predecessor/engine. Existing native execution, source/candidate, save/reload, joined-campaign and release checks remain required. Omitting the maintenance context retains the original engine authority checks.

The release engine runner (`Invoke-MIR42FourTargetEngineRun.ps1`) requires `-LibraryBindingsPath`: a small local JSON object mapping each selected target (`f210` through `f013`) to an absolute flat-library directory. These are local bindings, not tracked workstation requirements. Its modern package workers forward `-LibraryDirectory`, historical fresh loads use the same activation adapter, and upgrade workers receive `-LocalModLibraryDirs`. Required candidate, predecessor and fixture archives must already be installed with the expected bytes; execution neither acquires them nor recreates retired profiles. Package smoke starts with defaults, disables unrelated installed mods, checks the loaded selection and restores prior controls on success or failure. The existing historical receipt retains `staged_candidate_sha256` for its reader contract; it now records the selected library archive's hash and adds `library_input_receipt`, with zero dependency payload copies, links and extractions.

The general validation runner's package smoke scenarios accept `-LibraryDirectory`; unmigrated runtime scenarios stop with `mir-validation-obsolete-runner` before constructing a mod directory. Use the migrated focused progression, upgrade and Library consumers for affected native work. This guard does not disable static checks or scenario listing. Checkout-internal immutable release-custody aliases remain permitted and are not game mod directories. `Test-MIR42NineTargetHistoricalEngineRun.ps1` exercises the actual fresh-load and package-smoke entry points using tiny archives and substituted actors; it is storage/oracle regression evidence, not a nine-engine qualification pass.

The 3.0 compatibility compiler needs tests for both positive emission and negative safety. The goal is not only "the mod loads." The goal is proving that MIR emits, skips, rejects, and reports exactly what the policy says.

Current verification selection uses the declared inputs in `validation/tests.yml`, the existing assurance classes and `.mir/test-impact.yml`. `Test-MIRResearchabilityPlanning.ps1` consumes both `researchability_planning.lua` and `lab_reachability.lua`; its registry input and receipt hashes must include both. `Test-MIRRecipeSourceEpoch.ps1` consumes `recipe_source_epoch.lua`. Both exact acquisition fixtures map to their existing consumers and affected science scenarios. The selector's own known static test has no additional native scenarios. Unowned fixtures and tooling scripts retain conservative coverage. These exact mappings retain the broader static harness policy and grant no native acceptance.

The selection contract itself can be checked without Factorio or dependency archives:

```powershell
.\tests\tooling\Test-MIRDevelopmentCISelection.ps1 -PureSelectionOnly
```

Native lab, emitted research, production, save, multiplayer and engine performance claims still need their selected current-package scenario. Normal serial tests launch directly against the engine-family archive library. Profiles contain only small selection definitions; do not create dependency copies, hard links, extracted mods or replacement modpack directories. Keep compact results and required reproducers after completion; removing an existing archive alias does not reclaim its displayed length while a master link remains.

The remaining native entry points that still call immutable, material-audit or performance staging fail immediately with `mir-native-obsolete-runner`, before resolving engines, constructing candidates or allocating a mod directory. This includes the six older Bob Tin audit consumers and their F200 variants, the material observers, historical private-runtime staging, the older package-retention runner, and both legacy performance campaign commands. The control-plane performance executor also refuses before creating its source overlay. ProcessIR's selected live-capture command now refuses before engine/archive resolution and output creation, including `-PublishReference`; its offline `-Check` path remains available. The retained internal capture controls use tiny checkout-local synthetic inputs and a substituted actor, granting no normal native-staging authority. Explicit candidate-binding checks and existing log-audit modes remain available without native execution. `PrepareOnly`, recovery and preflight switches do not authorize staging. Their scenarios and historical evidence remain preserved; this refusal does not complete their migration or qualify their player outcomes. A required affected scenario must be converted to the existing direct-library activation before it can contribute new release evidence.

The library activation suite invokes these actual entry points in fresh noninteractive PowerShell hosts with absent inputs and checks the retirement error and absence of output. It also retains the switching, recovery, exclusion, hash and relocation checks below. These are host-side storage-policy checks, not replayed gameplay campaigns.

`Test-MIR42CapOwnershipMultiforce.ps1` now selects the supplied F210 library directly. `-PrepareInputsOnly` builds only its three owned assertion/blocker fixtures and two small settings archives for separate installation. Settings versions `0.1.200` and `0.1.203` select cap zero and three; they are not MIR distribution versions. Each create/server/reload invocation verifies the exact loaded selection and restores the preceding controls. The existing force-reset, merge/index-reuse, late-mutation refusal, earned-level and serialized-reload assertions remain intact. The controlled staging test exercises all five selections and repeated activation with no dependency copies, links or extraction.

The 8 October channel review compares both complete 2.1.20/2.1.21 API documents and all 67 intervening changelog entries with the current source and selected cap fixtures. It finds no mandatory API migration and preserves the 2.1.18 product floor. The current V3 cap admission now binds 2.1.21.87673, Steam build 25749703, the executable, APIs, changelog and five bundled mod identities. The existing policy writer's `-RefreshCapAdmission` consumes a hash-verified engine resolution, explicit recording time and exact preceding admission hash; it verifies actual installed bytes against the reviewed channel and exact schema before writing. V2 and historical policy records remain immutable. This admits only the two named harnesses. At that checkpoint the obsolete-runner guard blocked their unconverted runner; its subsequent direct-library conversion is recorded below. Neither an older native pass nor qualification/publication authority transfers. Current-package multiforce native acceptance is recorded below under its exact inputs.

Direct-library restoration retains its exclusive lock and archive read handles while waiting up to three seconds for the final process enumeration to clear after monitored shutdown. This wait never terminates a client. Initial admission still refuses a running client immediately; a persistent client prevents restoration and retains the durable recovery journal. The focused library controls exercise both delayed exit and persistent-client refusal. A terminated native run must still satisfy all scenario assertions before its result can pass.

The fresh F210 multiforce run passed at harness source `7c2409cfc6fc96c306a87c1c1c4e91ef7df05c67`, using candidate C SHA-256 `A3813E4B7ECB3AE030A1BD2121A9CE6E5B7B7778296ADEF5AC4A8BFE11EF5D03` and Factorio 2.1.21.87673. Result `build/p/m421-f210-cap-current-native-b/ea344583a8904057927b579ae5715a13/result.json` has SHA-256 `0D5C42C773B7BD5DD427D3947551D6A19979CCBB0DFC4DA5DE7A09717ED19FA8`. The original assertions cover cap zero/three/removal, earned level four, foreign-disabled state, native queue ownership, force creation/reset/merge and index reuse, forged-policy and late-prototype refusal, and the serialized final reload. Six native invocations restored all six library activations, with zero dependency copies, links or extraction. Peak monitored working set was 736,800,768 bytes under a 1,024 MiB workload budget. The first attempt's shutdown-restoration failure and recovery remain separate evidence. This is the named cap scenario, not historical V2/V3 migration, physical multiplayer, Library UI or complete release qualification.

`Test-MIR42F200SettingsCapTransition.ps1` is converted to direct-library execution. Supply `-LibraryDirectory`, the exact F200 engine, current candidate and materialization receipt. `-PrepareInputsOnly` prepares the owned assertion archive and two tiny settings fixtures inside the checkout; install them once into the selected library. The settings fixture versions `0.1.100` and `0.1.103` identify cap zero and cap three respectively and do not number MIR distributions. Native execution verifies their members against the existing settings writer, selects their exact versions, starts each stage with default settings and restores the previous controls after the engine exits. It writes no candidate or dependency archive and creates no archive links. The original uncapped → cap three → uncapped save lineage, enablement/visibility ownership, disabled expansions, loaded-mod closure and completed-save predicates remain required. Source-side A/B/A, hash, exclusion, concurrency, restoration and actor tests do not establish this native result.

That native transition passed on Factorio 2.0.77 at source `0b1a1e38c26fd4f38203031e3f9700b988785589`, using current F200 ZIP `F1593383638A6BD4C0070A59D8B8C766B9EECDC8FBF2E879F82AF550516E3B01`. Result `build/p/m421-f200-cap-direct-native-b/621509257a3f4f8b9caf13f666748381/result.json` has SHA-256 `02B6CC13D7496A551C586A842127283287BF7D60516308A887649B8B989A77AF`. Cap three disabled level four; removing the cap restored MIR-owned enablement while independently disabled research remained disabled. Earned levels survived both configuration changes and completed saves. All three activations restored controls, with zero candidate/dependency copies or archive links. The first attempt's fixture-member refusal remains preserved; ordered metadata generation fixed its nondeterministic `info.json` without weakening byte comparison. This does not qualify F210, multiplayer, graphics or upgrades from another MIR package.

The existing compatibility runner accepts a `LibraryActivation` for create and reload. `Start-MIRLibraryActivation` validates the profile's exact versions, selected archive hashes and dependency constraints, disables every unselected installed name, and holds selected archives open for reading. It switches only `mod-list.json` and the explicit settings input (or defaults). A durable journal preserves the previous small controls before replacement; the next invocation recovers an interrupted owner before selecting another profile. `Complete-MIRLibraryActivation` restores the previous bytes after all clients exit. The engine's `write-data`, saves and logs remain in the existing approved run directory. Updates and `--sync-mods` are rejected.

`tests/tooling/Test-MIRLibraryActivation.ps1` exercises A/B/A selection, pinned versions, missing/incorrect dependencies, settings isolation, interrupted-owner recovery, exclusive access and the existing create/reload collectors with tiny archives. Its native actor is substituted: these checks do not establish Factorio loading, graphical startup or gameplay. Remaining native consumers still require conversion and selected engine checks; they may not recreate retired profile archives. Two simultaneous clients requiring different active controls need a separately qualified arrangement; they must not silently recreate populated profiles.

The existing `scripts/Measure-MIRPerformanceRegression.ps1` offers a bounded `-ObserveResearchAll` mode for the reported mass-research regression. Supply `-Target f200|f210`, the exact `-Candidate`, `-SourceMaterializationPath`, published `-PriorRelease`, current `-ExpectedSourceCommit`, explicit `-FactorioBin` and `-LocalModZipDir`, and checkout-local `-ArtifactRoot`. `-PrepareResearchAllInputs` prepares only the tiny MIR-owned assertion ZIP for separate installation into the selected library. Tracked `fixtures/run-profiles/research-all-*.json` pin the engine, published predecessor and default base-only scope. The runner creates private saves, measures the first and repeated native commands with completion-event counts, verifies the actual loaded selection and restores each library activation. It preserves native profiler logs and reports a single paired observation; it does not establish a statistical performance budget, GUI responsiveness, multiplayer, save migration or the whole legacy campaign. The default campaign path remains retired.

The maintainer-authorized profile retirement on 7 October removed all 2,041 archive entries after verifying surviving master file identities and all 473 backup files by SHA-256. The backup replaced the old directory. Definitions and four distinct tiny RIC settings fixtures remain in primary-checkout custody at `build/handoff/MIR421_SOL_CURRENT/profile-retirement-2026-10-07`, with the complete retirement receipt. No dependency archive was copied or linked. The observed free-space delta was -1,126,400 bytes during preservation and removal: displayed alias lengths were not reclaimed physical storage. This custody records old provenance, not current native acceptance or permission to recreate old paths.

The external `testmods` location may be deleted. It is not part of the repository's portable contract: pass an explicit library location containing the required exact releases on each machine. K2 and Tin continuation consumers have no machine-specific library default. Source-only checks need no library. Existing legacy hard-link helpers now reject either endpoint outside their executing checkout before linking or entering copy fallback; they do not make unconverted native runners ready. Only the direct-library path is admitted for normal dependency use.

`Test-MIRF210CurrentBobTinLevel4Continuation.ps1` now uses that direct-library path for both create and reload. Supply one `-LocalModLibraryDirs` entry, `-FactorioBin`, the current `-CandidateZip` and `-SourceMaterializationPath`, and the small exact `-SettingsPath`. Required dependency versions/hashes and the level-three-to-four, +8%, 108-plates-from-100-ore witness remain in the tracked continuation dossier. Install the owned assertion ZIP separately once; its members must match the current fixture. The runner records private initial/final settings and restores the prior controls. Old populated-stage/recovery options refuse before staging; historical V1 results remain under their original source and receipts. The current runner emits V2 results. Without explicit engine arguments it retains the dossier's exact 2.1.20 binding. A fresh observation may supply both `-ExpectedEngineVersion` and `-ExpectedEngineSha256`; the executable and native version report must match, and the original create/production/reload assertions still run. `-SettingsMode Defaults` explicitly starts without inherited settings; file mode still requires the retained settings hash. Results identify the actual engine and settings separately from historical provenance. A new input binding transfers no prior pass. Tiny selector, launch, loaded-selection and reload controls establish the storage conversion, not a new native production pass.

The fresh Bob-only observation on 8 October passed on Factorio 2.1.21 with default settings, source `ffc72dea1f9cfcd012bbe4bcfb7239abbcb0ff37` and F210 archive SHA-256 `8E3028893DDFEB949A1DE316246E29D07BF5C5D242A33E9413A2FF930B3D1A43`. Its result is `build/p/m421-tin-ordering-native-f/9e7b439251694ce5b1fb8bfb0a931ddd/result.json`. The unchanged oracle observed finite levels one through three, continuation level four, a 6% to 8% recipe bonus and 108 plates from 100 ore after reload. Create/reload took 80.04/82.07 seconds. Both used the shared library directly; previous controls were restored, with zero dependency payload copies, links or extraction. This is exact Tin/default-settings evidence, not Bob/Angel combined coverage, a tested cap boundary, F200 acceptance or final release qualification.

That run repaired an upstream-finalizer ordering defect: MIR previously compiled before Bob's Electronics and Technology completed their lab/science changes. F210/F200 metadata now contains hidden optional ordering dependencies for both. A separate late module import also prevented another mod from inspecting the lab acquisition service; the item index now loads in MIR's module scope. The failure-only fixture retains a small post-MIR acquisition observation, including indeterminate trace limits. These observations are not clean compiler replay inputs, and a diagnostic error cannot replace the original Tin assertion failure.

The follow-up at source `aa207cf620535efbfadd12939e0aa3612678ab69`, F210 ZIP SHA-256 `834F1A4730E8711DDBD45581C2723CF7A4D1558341CBF5DC4CB52FC47A74BAAF`, prefers independently acquired machines before exploring their research-gated alternatives. The same engine, Bob releases and default-settings scenario passed in `build/p/m421-machine-native-run-a/9874d197e1b54445b46f1057cab49426/result.json`: level four retained the 8% bonus and produced 108 plates after reload, with controls restored and zero dependency copies, links or extraction. Create/reload took 62.65/66.87 seconds versus the preceding 80.04/82.07 seconds. These are single observations on this host, not a statistical benchmark or broader ecosystem acceptance. Controlled counterfactuals require an initial machine to avoid unrelated technology queries while retaining unavailable, circular, fixed-recipe and necessary research-gate cases; the existing fluid, surface, source-epoch and progression checks remain selected.

The current nine-target construction from `16dddc242c92cf41d6ca55cf4fe63c9c222d7911` was checked again on that exact F210 engine and Bob tuple with default settings. Archive SHA-256 `7A09221BABDBC2F79C930C101E14F76E43858E5DED17A8ABCED46366125F2258` passed the unchanged level-four, 8% and 108-plate reload assertions in `build/p/m421-current-tin-native-b/7dbd1ccdb0a84653bdb12c2dd863b465/result.json` (SHA-256 `2A414E96982B7EA43B9C23ED807EAF2582D2C9C8FCA7CAB87AAE30C7508FFDC6`). Create/reload took 65.53/68.64 seconds, with prior controls restored and zero dependency archive copies or links. This is current-package Bob-only Tin evidence; the preceding observations retain their original identities and the same broader limitations.

The prepared `Test-MIRK2213ImersiteContinuation.ps1` consumer uses direct activation. Supply its current candidate/materialization receipt, `-InputProfilePath fixtures/run-profiles/k2-213-imersite-f210.json`, an explicit `-FactorioBin` and one `-LocalModLibraryDirs` location. The tracked profile pins the 2.1.21 engine/runtime API and seven exact dependency archives; no private receipt or retired profile path is needed. `-V5ObservationResultPath` remains an alternative for the distinct historical 2.1.20 input lock, never a substitute for current qualification. The two input forms are mutually exclusive.

The selected library must already contain the exact archives and the `0.1.2` continuation fixture ZIP, whose members are checked against current source. Acquisition and fixture construction happen once, separately. The fixture explicitly enables MIR's diagnostic report; other startup settings use defaults. Preflight refuses missing versions, changed hashes, extra selections, inherited settings or stale fixture members. The runner preserves the existing level-four/next-level-five, 8% powder bonus, separate 10% crystal owner, 42% queued-progress and single-reload oracles, and restores prior library controls. The native budget charges active controls and recovery-journal bytes as well as run output; existing archives add no payload writes. The V2 result binds the selected input profile or historical observation separately, including on a failed native attempt. Controlled input tests and a completed preflight do not qualify the gameplay outcome on the current package.

The 8 October native attempt exposed two distinct defects: candidate C omitted Imersite's continuation on 2.1.21, and the loader-line inventory omitted K2's two asset-only mods. The player correction admits the exact reviewed engine through `K2SciencePhasePolicyV5`; historical policies and route-safety certificates remain unchanged. The fixture now reports the complete engine `mods` table through an explicitly requested, source-bound observer. The collector rejects missing, extra, duplicate or wrong-version identities, another mod's observation, and contradictory loader lines. Other runners retain their existing inventory check unless they explicitly supply an observer.

The corrected F210 ZIP `241B17EB7D572DC037E32280BD45B1793D9B75EA0B4FFF26F80090CA9DA7076A` passed fresh creation and one unchanged-save reload on 2.1.21 with K2 2.1.3/K2SO 2.0.13. Receipt `build/p/m421-k2-current-native-c/40b48b585ff648f39f036234e8cdbf9b/result.json` has SHA-256 `F028CE13E20F0D40B09519BE4A55FB561726D5526DAB742E19812D24E97C5644`. It proves the finite level-three stage, completed level-four powder bonus of 8%, separate crystal bonus of 10%, and next-level-five queue at 42% after reload. All fourteen selected identities matched; three governed actors peaked at 965,644,288 bytes working set within the 1,024 MiB limit, with unchanged reserves, restored controls and zero dependency copies or links. This first receipt is reward/state evidence; the additional production observation follows.

Fixture 0.1.3 extends that same candidate and exact profile with paired native crushers. Receipt `build/p/m421-k2-production-native-a/a580bbb5d6064d1aae96c1df0a1af19c/result.json` (`4D433FC7A8944B922C9CAC0A4216945CF441C1E9467CC97331258269CDCF2971`) passed at harness source `d8311d385af904926fc0668ec902df85e7286c5b`. After reload, 300 ore produced 324 powder and 324 sand for the force with the earned 8% bonus, versus 300 of each for the unresearched control. The fixture supplies ingredients and energy but changes no recipe, machine speed, modules or beacons. The 25,000-tick reload preserves the previous research/queue/progress assertions and captures actual output counts separately. Three actors peaked at 903,385,088 bytes working set and 856,203,264 bytes sampled private memory under the same 1,024 MiB allowance. Controls were restored; dependency copies, links and extractions were zero. This proves the named crusher route's output after reload, not natural acquisition, a published-predecessor upgrade, two reloads, other K2 routes or joined release acceptance.

The existing manifest-driven `tests/runtime/Test-MIRUpgrade.ps1` also selects predecessor and candidate versions directly in one explicitly supplied library. Both exact MIR archives and the selected assertion fixtures must already be installed there; source-only fixtures are disabled for the candidate phase. The source phase's writable settings are preserved privately and activated for the candidate. Each owned engine invocation verifies the library/configuration and reads back the loaded mod versions; existing source, earned research, reward, save-completion and reload oracles remain required. Result schema 3 records `source_library_activation` and `library_activation`; it does not represent these as hard-link leases.

For current F210/F200 published `CCC00 → CCC01` base and Space Is Fake checks, `-SourceMaterializationPath` selects the canonical receipt instead of `-SelectedReleaseManifest`. It checks the supplied archive against current player-source bindings, allowing test or documentation changes without rebuilding identical player packages. It retains the actual published-predecessor custody checks, exact transition and scenario selectors, retained output, native loaded-selection checks and two reloads. Results bind the materialization receipt, player fingerprint, harness bytes and actual worktree state. This mode does not grant frozen-source release acceptance; the separate seal reader still requires the frozen committed source.

The E F210/F200 base upgrades and E F210 Space Is Fake upgrade completed through this path, including both reloads. The [candidate matrix](../releases/mir42-nine-target-candidate-playtest-matrix.md#mir-421-private-construction) binds the three result hashes to their exact candidate and clean harness source, alongside the E paired mass-research observations. It also retains the current Tin memory stop and F200 Space Is Fake admission refusals; these cases remain unqualified. Missing inputs and capacity failures block their selected native case, rather than unrelated source work or already-completed cases.

`Test-MIR42V2V3CapMigration.ps1` now uses the direct master library with explicit `-LibraryDirectory`, engine, pinned private V2 archive and current candidate/materialization receipt. Its preparation-only mode writes four small assertion versions and cap-zero/cap-three settings versions `0.1.310`/`0.1.313` inside the checkout for separate one-time installation. Native stages verify their exact members, pin every selected version, establish default settings, preserve private outputs and restore controls after each actor. The pinned private V2 input shares the public predecessor's numeric identity but has different bytes; it must have one unambiguous verified library selection and must never be described as the published 4.2.0 upgrade. The original owned/foreign enablement and visibility, cap restoration, queue, 42% research progress, save-lineage and completed-save assertions remain required. Source controls grant no new native migration pass.

Its K2 maintenance case selects `-FixtureName assert-upgrade-k2-imersite-4-2-21000-to-4-2-21001 -K2ImersiteInputProfile fixtures/run-profiles/k2-213-imersite-f210.json`, exact `-FromVersion 4.2.21000 -ToVersion 4.2.21001`, and `-SelectedTarget f210`. Supply the current candidate manifest or its canonical `-SourceMaterializationPath`, plus the published-predecessor manifest, engine and one library explicitly; omit `-Archetype`. `-PrepareInputsOnly` prepares the small owned assertion/settings ZIPs for separate installation without touching library controls.

Run the two K2 cap cases separately. Default `-K2ImersiteCap 3` retains the published default without a settings override and requires continuation to remain withheld. `-K2ImersiteCap 0` uses the existing settings override writer to select zero explicitly. Both seed three earned predecessor levels and require their finite-domain migration, 6% powder/10% crystal rewards and copper level-three queue/completed work to survive. The zero-cap case then completes newly available continuation level four and verifies 8% powder, independent 10% crystal, and next-level-five queue at 42% through two distinct reloads. The cap-three case verifies the retained copper queue and bonuses through both reloads. Complete-mod observation includes K2's asset-only dependencies. The first native attempt rejected an incorrect fixture assumption that the published default was zero; that failed attempt establishes no upgrade pass. Exact corrected-case receipts remain required; preparation, controlled checks and the earlier fresh-game production receipt do not supply those results.

`Test-MIRCommunityPowerManufacturing.ps1 -Target f200|f210` selects the exact Solar Matrix/Accumulator V2 pair from `fixtures/run-profiles/community-power-<target>.json`. Supply the engine, library, candidate and materialization receipt explicitly. Its preparation-only mode writes a small owned fixture archive with target-specific metadata and shared assertion code for separate one-time installation. The native oracle checks the upstream shared unlock, one MIR manufacturing owner and the 5% first-level bonus, then compares actual production from twenty unmodified crafts on researched and unresearched forces (21 versus 20 items for each recipe). It supplies ingredients and machine energy at game speed 64, with no modules, beacons or recipe edits. Its loopback-only owned server stops only after observing both the production result and completed save; a fresh native load checks the saved facts and bonuses. It records exact inputs and restores library controls. Preparation and source checks alone grant no native pass; SE, AAI, Paracelsin and enabled DLC remain separate profiles.

The exact paired scenario first passed on 8 October at source `1798f1b2151430f0161e4176b586f6f95961efab`, Factorio 2.0.77 and then-current F200 candidate `F1593383638A6BD4C0070A59D8B8C766B9EECDC8FBF2E879F82AF550516E3B01`. Both recipes produced 21 items from twenty crafts with the first research reward, versus 20 on the comparison force; all ingredient inputs were consumed and both 5% bonuses survived save/reload. Result `build/p/m421-community-power-native-b/3d4b0962d9964680ada08788629b87f7/result.json` has SHA-256 `3FD18D44E84CFA505D2B6C2A11568C5153C2BA285AB21940902E0A95B40E328D`. The earlier benchmark-only attempt produced the expected items but failed the save requirement and remains failed at `build/p/m421-community-power-native-a/ede10eaf501b415c9f176b93db06e458`. The successful run restored controls and made zero dependency copies or archive links. This closes the named paired manufacturing witness, not the other community profiles or release acceptance.

After the DLC locale refresh, both targets passed the same production and save/reload assertions at harness source `c9b632d4c93cc03f526431326a0c5f0925a42257`, using candidates constructed from `eb74d2e7d6223d9a8c284060f5f4c8b31a68f54a`. F210 used Factorio 2.1.21, SolarMatrix 1.0.9 and Accumulator-V2 1.0.8; F200 used 2.0.77, 1.0.8 and 1.0.7 respectively. Each completed three native actors and restored controls, with zero dependency payload copies or archive links.

- F210 candidate `A3813E4B7ECB3AE030A1BD2121A9CE6E5B7B7778296ADEF5AC4A8BFE11EF5D03`: `build/p/m421-community-power-current-native-d/f210/d607c8ee74174956b493ce04d111c47c/result.json`, result SHA-256 `701BDF8949C62D3106ACF51C602A3D54541E2813AA16EEEC8D1FE4E5CEB60D6E`.
- F200 candidate `2ED9D135408BC1D97ACD00691C54BB22186DA2C0EEDB341D7BD0F2ECBB775D6A`: `build/p/m421-community-power-current-native-c/f200/59ff5970ee3442d08a5b2327419833ba/result.json`, result SHA-256 `4644DF77914367B3966CABC710E0E802919CE2A953CEF6EBD3C0B52C828A3E32`.

The initial F210 attempt was refused before launch with a 1 GiB workload allowance. The selected retry used 768 MiB, informed by retained same-engine headless observations up to 630,865,920 bytes, and observed a peak working set of 428,998,656 bytes. System reserves and live enforcement were unchanged; `build/tmp/mir421-community-power-f210-memory-observation-d.json` records that estimate's limited applicability. The F200 pass was retained without repeating it. These results do not establish enabled-DLC behavior, general science progression, other mod combinations, published-predecessor upgrades or final release acceptance.

The later E candidate passed this same affected manufacturing scenario on both exact modern profiles at harness source `1ac2711694b0da03ab829f904660d45ac821eb88`. The [candidate matrix](../releases/mir42-nine-target-candidate-playtest-matrix.md#mir-421-private-construction) records the new archive and result hashes separately from C/D. Each target again produced 21 versus 20 items for both recipes, preserved rewards and production facts after reload, restored controls and created zero dependency archive copies or links. No fixture ZIP or dependency archive was rebuilt for these runs. The earlier results retain their own identities; broader profile, progression, upgrade and release boundaries remain unchanged.

`tests/runtime/Test-MIRResearchBrowser.ps1` uses the same direct-library path. Supply `-FactorioBin`, `-CandidateZip`, `-LibraryDirectory` and `-Target`; the runner verifies the engine line, current Library modules, installed candidate hash and every assertion-fixture member before activation. It selects only base, MIR and its assertion fixture, establishes default settings, verifies the loaded selection for each create/benchmark/reload, and restores the previous controls. `-PrepareInputsOnly` constructs the small owned fixture ZIP inside the checkout without requiring an engine, candidate or library and without native execution. Install that prepared fixture separately once. Runtime receipts record `library_activation`, not an immutable-input lease. The existing `-Graphics` player, localization, GUI and save/reload assertions remain required for those claims; host adapter controls establish no graphical or gameplay pass.

For optional-artwork acceptance, select `-DlcIconCase Defaults`, `RawOptIn`, `ImportedOptIn` or `RawOptInImportedOff` consistently during fixture preparation and execution. The fixture first verifies the production checkbox remains default-off, then sets only the requested test defaults and an actual MIRSET1 import where selected. Native creation writes the binary settings subsequently read by graphical startup and reload; the receipt retains a private hash-verified settings snapshot. Post-MIR assertions verify raw/imported precedence, both shortcut sizes and absence of Space Age/Elevated Rails resource paths throughout final technologies and shortcuts. Each engine invocation must produce exactly one matching observation. This extends the existing base-only selection, not the installed engine: a run with DLC installed but disabled does not establish physical-absence qualification. The default `None` keeps ordinary browser acceptance unchanged.

Graphical acceptance defaults to `-GraphicsPreset low`; `very-low` selects Factorio's documented lower graphics preset while retaining the actual graphical client, icon, localization, GUI and reload assertions. Successful results record `graphics_preset`. This changes the selected workload, not the resource governor's reserves or the declared process allowance. The consumed launcher checks verify argument forwarding. A preset option or admission refusal establishes no native pass; record the actual selected preset when comparing performance results. See [Factorio's command-line parameters](https://wiki.factorio.com/Command_line_parameters).

Estimate a native process allowance from both working-set and private-memory observations. The governor enforces both against the same declared allowance; a working-set peak alone can underestimate graphical loading. New process ledgers retain the triggering over-budget sample, its allowance and `peak_sampled_private_bytes`; completed and interrupted summaries also retain that sampled private-memory peak. Sampling can miss peaks between observations, so these values are observations rather than hard upper bounds. The resource-recovery controls inject each over-budget metric separately while supervising real small child processes, verify cancellation and retained evidence, and leave the physical-memory, commit and disk reserves unchanged. They neither exhaust host memory nor establish Factorio acceptance.

The personal-state lifecycle runner now accepts explicit `-LibraryDirectory` and `-FactorioExe` inputs and selects archives directly. Use `-Operation PrepareInputs` with the selected target, input mode and candidate to prepare its small owned fixture ZIPs separately; this mode performs no Factorio execution or library activation. Install those exact fixtures once, then use the default `Run` operation. Each phase binds the installed candidate bytes and every fixture member, establishes defaults initially, carries a private settings snapshot forward, and restores prior library controls after all owned processes exit. Removal disables MIR in the active selection while retaining its archive. Current V2 governed results contain `library_input_receipts`; historical lease receipts retain their original identities.

Within one lifecycle phase, the owned server and clients use the same fixed mod-list and settings. Additional client admission verifies every live engine is a still-owned direct child, checks the selected engine and configuration, and reads the selection without rewriting it. An unrelated engine, reused process identity or changed selection is refused. All three logs must match the selected mods and versions. This host-side arrangement still needs current native two-client acceptance; it supplies no physical-input or multiplayer pass by itself.

The shared native-probe driver explicitly waits for its native child and propagates that child's exit code. PowerShell's call operator returned early for the Windows GUI executable during the first direct browser attempt, leaving only Factorio's startup header before the governor stopped the owned tree. The loaded-selection check rejected that attempt. A tiny delayed Windows GUI executable reproduces the premature return with the old driver and completes with the explicit wait; the controlled resource suite retains that regression alongside argument, environment and output-budget checks. Engine loads and graphical assertions remain separate native evidence.

The browser failure receipt preserves the original engine/resource error separately from control-restoration status. If the engine has not fully exited, restoration remains refused and the durable library journal stays available for recovery. That cleanup refusal must not replace the primary exception. Tiny-file controls execute the runner's actual catch block for successful cleanup, delayed-shutdown refusal and exhausted receipt budget; they launch no engine.

The browser fixture observes the base recipe schema to select F210 `categories` or F200 `category`. Its native discovery witness waits for two unchanged client-display observations before opening the Library: graphical startup applies the window resolution and scale after the save's first tick. The original root, search and filter must then remain intact throughout discovery. Twenty-six controlled opposing cases cover startup, later invalidation, disconnects, deadlines and translation completion. This setup correction changes no player UI behavior and does not waive widget-preservation assertions.

Use the same upgrade command with `-PrepareInputsOnly` to generate the small specialized MIR-owned assertion ZIPs inside its approved build root. The preparation receipt lists their exact identities and any selected SIF dependencies, and explicitly says `prepared-not-native-tested`. This mode starts no engine and writes no archive library. It has its own small-output capacity check; normal execution retains the native reserve and declared memory budget. Supplying a construction manifest still requires the existing clean-source check. Acquire or install only these selected inputs separately, then run without `-PrepareInputsOnly` and supply `-LocalModLibraryDirs`. Neither step reconstructs historical populated profiles.

The first direct-library SIF native attempts exposed two input/fixture failures, before candidate acceptance: Factorio 2.1.21 rejects the removed `fuel_category` field in Space Is Fake 1.0.76, and the F200 base-only fixture selected `mining-productivity-4` although enabled Space Age removes it. The F210 scenario now pins upstream Space Is Fake 1.0.78 with cr-commons 1.0.33; those exact acquired bytes require fresh execution. The SIF specialization uses Space Age's infinite `mining-productivity-3` for the F200 level/queue check, preserving level 5 and 37% progress. Ordinary base-only fixture input is unchanged. These corrections do not turn either failed attempt into a pass.

When the hosted `static.mir4-platform-preview` worker fails on a stale generated projection, the same worker can preserve a separate SDK generation repair artifact. It invokes the existing complete fixed-point writer from the exact clean checkout and exports only changed files returned by that writer, with paths, hashes, source commit/tree, player-source fingerprint and run identity. The output is limited to 16 MiB; no player package or dependency archive is constructed. The original test and verification gate remain failed. Before adopting these bytes locally, verify the producer and exact source, all file hashes and generated path scope; preserve any local changes. Commit the generated corrections and obtain fresh required checks before integration. This artifact provides generated source for repair; it grants no native, release or signing acceptance.

The E construction passed affected headless DLC and Library checks on 9 October at harness source `7065798b7c9379f60e2241b34b2f9b2221aab76a`. F200 selected `RawOptIn` on Factorio 2.0.77: the raw and effective option were true, both shortcut sizes used base lab artwork, and 255 final technologies with 3,743 artwork strings contained zero inactive Space Age/Elevated Rails references. Result `build/p/m421-browser-current-e-headless-a/94353df179104e1782fb025fde4c9451/result.json` has SHA-256 `EAA8F53C79A73856A0BAFD3D4B8D208CC35115D0EA1A1ED16A443A10E26A0073`; package SHA-256 is `EDD4A15F1C405C4B2F8487D86FC16F8C0A06470F71D3B4D05B4CAB8329D41732`.

F210 selected `ImportedOptIn` on Factorio 2.1.21: raw false, imported/effective true, both shortcut sizes using base artwork, and zero inactive-provider references across 254 technologies and 3,720 artwork strings. Result `build/p/m421-browser-current-e-headless-b/c5d3352453824d3da90a844e29fde05f/result.json` has SHA-256 `70D393A10E35C0FD625AE57F40C874B80F30069CBFFB5181E54074AFD27E9BB9`; package SHA-256 is `5B1F56479D490DCA116EC373809C63138513B5A7AEBDDE1871DAB7373709A396`.

Each completed three native actors under a 512 MiB workload allowance and 120 MiB output budget, with unchanged system reserves. Monitored working-set/private peaks were 418,742,272/348,532,736 bytes on F200 and 435,658,752/370,782,208 on F210. Both restored library controls and created zero dependency copies, archive links or extraction. The first F210 prevalidation refusal remains recorded separately; the completed run followed a fresh measurement that admitted the unchanged allowance.

The 630 F200 and 757 F210 Library assertions exercise controlled models inside the actual engine. Neither case had a connected player or ran graphical texture loading. These records establish the named current-package prototype and headless boundaries; graphical startup, physical DLC absence, connected-player GUI, two-client multiplayer and final joined acceptance remain open. The older graphical records keep their original source and package identities.

Candidate E's F200 Space Is Fake upgrade passed on Factorio 2.0.77.84539 at clean harness source `2b1177c4c68648c2ae6c2a38d4413bee21706d46`. Result `build/p/m421-current-sif-upgrades-e-capacity-e/f200/result.json` has SHA-256 `EE266DC4C7218DECD3BA573816B9670245C1A3C03D18E08EDCB881F12763FE89`; candidate ZIP hash is `EDD4A15F1C405C4B2F8487D86FC16F8C0A06470F71D3B4D05B4CAB8329D41732`. Four serial native actors checked the published `4.2.20000` predecessor, both level-seven continuations and finite anchors, earned speed rewards, five retained paid manufacturing identities and their saved queue/progress, and eleven native recipe bonuses through two reloads. The direct-library transactions restored both control sets with zero dependency copies, links or extraction. Working-set/private peaks were 634,789,888/634,437,632 bytes under a 768 MiB workload allowance and 120 MiB output budget. That allowance was derived from the same engine/dependency/fixture case's measured peaks with at least 20% margin; system reserves, watchdog and oracles were unchanged. Readback is `build/tmp/mir421-current-e-sif-f200-readback-e.json`. This completes this selected E upgrade case, not graphical, crafting, multiplayer or final release acceptance. Earlier admission refusals remain failures; they were not rewritten as passes.

Current E also passed the selected Bob-only Tin level-four production/reload check and both K2 published-predecessor upgrade cases at clean harness source `d0ad51788117bd8fdeb93eeb03505572ad4c679e`. Tin produced 108 plates from 100 ore after reload with an 8% bonus. K2 preserves default cap three and its earned rewards; explicit cap zero completes level four and retains queued level five with 42% progress through two reloads. Each restored library controls with zero dependency copies, links or extraction. The [candidate matrix](../releases/mir42-nine-target-candidate-playtest-matrix.md) records exact inputs, hashes, resources and non-claims. Readbacks are `build/tmp/mir421-current-tin-readback-f.json` and `build/tmp/mir421-current-k2-readback-h.json`; frozen-source joined acceptance remains open.

The [candidate matrix](../releases/mir42-nine-target-candidate-playtest-matrix.md) retains the original E F210 Space Is Fake pass and a separately identified repeat with the current harness, together with three F210 mass-research pairs and the F200 pair. Those timing observations retain higher candidate medians and host variability; they are not performance acceptance. Earlier resource refusals remain preserved alongside later exact-scenario passes.

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

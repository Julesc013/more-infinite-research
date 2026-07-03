# Test Results

This file records local release-candidate validation runs. It is not a substitute for the manual mod matrix in `docs/compatibility.md`.

## 2026-07-04 Extended Audit Gate Hardening

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.

Scope:

- Added strict audit pass/fail semantics to `Invoke-MIRExtendedTests.ps1` with `-FailOnAuditFailures`.
- Added `-CollectAll` as the explicit exploratory mode so overnight audits can collect every selected scenario instead of stopping at the first failure.
- Added per-scenario Factorio load-test timeouts with timed-out processes killed and grouped as `timeout` failures.
- Exposed `-FromLockfile` through the extended wrapper for reproducible sharded reruns.
- Made unresolved required dependencies skip load startup by default and group as dependency failures unless `-ContinueOnDependencyFailure` is passed.
- Added reviewed expected-failure classification via `fixtures/compat-matrix/expected-failures.json`, with strict gates failing on unexpected groups.
- Switched `AuditSmoke` to the deterministic committed `space-age-baseline` manual-scenario metadata path so strict release gates do not depend on volatile Mod Portal catalog ordering.
- Updated README, architecture, compatibility, release notes, roadmap, manual test plan, release plan, changelog, TODO, validation snippets, and the self-hosted workflow to document the strict/exploratory split.

Commands:

```powershell
$scripts = @(
  'scripts\Invoke-MIRCompatAudit.ps1',
  'scripts\MIRCompatAudit\FactorioRunner.ps1',
  'scripts\Convert-MIRCompatAuditResults.ps1',
  'scripts\Invoke-MIRExtendedTests.ps1',
  'scripts\Invoke-MIRValidation.ps1'
)
foreach ($script in $scripts) {
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $script), [ref]$null, [ref]$errors) | Out-Null
  if ($errors) { throw ($errors | Out-String) }
}
.\scripts\Invoke-MIRCompatAudit.ps1 -CandidateNames definitely-no-such-mod-mir-test -MaxCandidates 0 -CatalogPages 0 -OutputDir .\build\compat-gate-failure-smoke
.\scripts\Convert-MIRCompatAuditResults.ps1 -AuditDir .\build\compat-gate-failure-smoke
.\scripts\Convert-MIRCompatAuditResults.ps1 -AuditDir .\build\compat-gate-failure-smoke -OutputDir .\build\compat-gate-expected-smoke -ExpectedFailures .\build\expected-failure-smoke.json
.\scripts\Invoke-MIRExtendedTests.ps1 -Tier AuditSmoke -OutputRoot .\build\extended-audit-smoke -FailFast -FailOnAuditFailures -ScenarioTimeoutSeconds 60
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRExtendedTests.ps1 -Tier Static,AuditSmoke -OutputRoot .\build\extended-gate-hardening -FailFast -FailOnAuditFailures -ScenarioTimeoutSeconds 60
```

Results:

- PowerShell parser checks passed for the changed audit, converter, wrapper, runner, and validation scripts.
- Synthetic missing-mod audit produced one grouped `dependency_resolution_failure` with `unexpected_count = 1`, proving strict gates have a machine-readable failure signal.
- Synthetic expected-failure conversion with a generated rule produced `expected_count = 1` and `unexpected_count = 0`.
- Grouped compatibility summary now reports the failure kind correctly in the by-kind table.
- Deterministic strict `AuditSmoke` passed through the wrapper and converter with `-FailFast -FailOnAuditFailures`.
- Static validation passed, including package parity, changelog format, compatibility automation wiring, and whitespace checks.
- Combined extended wrapper gate passed for `Static` and `AuditSmoke`.
- Runtime validation and credentialed top-25/manual/full Mod Portal load audits were not rerun in this documentation-only gate-hardening pass.

## 2026-07-04 Overnight Progress Output

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.

Scope:

- Added per-scenario start/result progress lines to `Invoke-MIRCompatAudit.ps1` load-test runs so unattended terminal sessions show scenario index, type, roots, dependency-failure count, pass/skip/timeout status, exit code, parsed audit-row count, and elapsed seconds.
- Fixed grouped-result conversion for single-root load results so skipped-load groups keep the full root mod name instead of indexing the first character of a scalar string.
- Updated README, compatibility docs, and changelog to describe the verbose overnight progress behavior and `Tee-Object` logging recommendation.

Commands:

```powershell
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts\Invoke-MIRCompatAudit.ps1'), [ref]$null, [ref]$errors) | Out-Null
if ($errors) { throw ($errors | Out-String) }
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRCompatAudit.ps1 -CandidateNames definitely-no-such-mod-mir-test -MaxCandidates 0 -CatalogPages 0 -FactorioVersions 2.1 -RunLoadTests -FactorioBin C:\Windows\System32\cmd.exe -OutputDir .\build\compat-progress-smoke
.\scripts\Convert-MIRCompatAuditResults.ps1 -AuditDir .\build\compat-progress-smoke
```

Results:

- Parser check passed for the changed compatibility-audit script.
- Static validation passed.
- Synthetic dependency-failure load-test smoke printed the new per-scenario start/result progress lines without launching Factorio, because the scenario was skipped before startup.
- Grouped result conversion passed for the synthetic progress smoke and reported the full root mod name for both metadata and skipped-load dependency-failure groups.

## 2026-07-04 Local Modpack Zip Audit Support

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.
- Local zip inputs under `tmp/`:
  - `all-the-overhaul-modpack_2.2.7.zip`
  - `kry-all-planet-mods_1.1.3.zip`

Scope:

- Added `-LocalModZipDirs`, `-LocalModZips`, `-LocalModNames`, and `-RunLocalModZips` to the compatibility audit runner.
- Added a `LocalModZips` extended-test tier.
- Added local zip `info.json` parsing, local `source_path` lock entries, and direct copying of local mod zips into isolated Factorio mod directories.
- Added `-IncludeRecommendedDependencies` so local modpack wrapper zips can include `+` dependencies as pack contents.
- Fixed dependency-name parsing for no-whitespace version constraints such as `base>=2.1.7`.
- Updated README, compatibility docs, changelog, TODO, and static validation snippets for the local modpack zip path.

Commands:

```powershell
$scripts = @(
  'scripts\Invoke-MIRCompatAudit.ps1',
  'scripts\Invoke-MIRExtendedTests.ps1',
  'scripts\MIRCompatAudit\DependencyResolver.ps1',
  'scripts\MIRCompatAudit\FactorioRunner.ps1',
  'scripts\MIRCompatAudit\ModPortal.ps1'
)
foreach ($script in $scripts) {
  $errors=$null
  [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $script), [ref]$null, [ref]$errors) | Out-Null
  if ($errors) { throw ($errors | Out-String) }
}
.\scripts\Invoke-MIRCompatAudit.ps1 -RunLocalModZips -LocalModZipDirs .\tmp -LocalModNames kry-all-planet-mods -IncludeRecommendedDependencies -MaxCandidates 0 -CatalogPages 0 -FactorioVersions 2.1 -OutputDir .\build\local-zip-smoke
.\scripts\Invoke-MIRCompatAudit.ps1 -RunLocalModZips -LocalModZipDirs .\tmp -IncludeRecommendedDependencies -MaxCandidates 0 -CatalogPages 0 -FactorioVersions 2.1 -OutputDir .\build\local-zips-both-smoke
.\scripts\Convert-MIRCompatAuditResults.ps1 -AuditDir .\build\local-zips-both-smoke
```

Results:

- Parser checks passed for the changed audit, extended wrapper, dependency resolver, Factorio runner, and Mod Portal helper scripts.
- Local zip smoke recognized `kry-all-planet-mods` as a `local_zip` scenario, wrote a local lock entry with `source = local_zip` and `source_path = C:\Projects\Factorio\more-infinite-research\tmp\kry-all-planet-mods_1.1.3.zip`, and recorded `66` dependencies from the zip metadata.
- The dependency parser no longer misclassifies `base>=2.1.7` as a portal mod name.
- Both-zips smoke selected two `local_zip` scenarios: `all-the-overhaul-modpack` reported one release-selection failure because it targets Factorio `2.0`, and `kry-all-planet-mods` reported dependency-resolution failures for unavailable or incompatible `2.1` dependency releases.
- Grouped result conversion passed for the both-zips smoke and reported those local zip issues as dependency-resolution groups.
- The smoke reported unresolved/incompatible dependencies as metadata failures; no Factorio load test was attempted in this metadata-only smoke.

## 2026-07-04 Release Documentation Synchronization

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.

Scope:

- Audited README, changelog, root TODO, roadmap, compatibility docs, architecture notes, manual test plan, release plan, release notes, mod portal copy, and test-results ledger after the extended audit automation commit.
- Updated the derived `2.1.0` release notes and mod portal copy so they mention executable manual scenarios, sharded/resumable Mod Portal audits, grouped failure reports, review-only profile-stub generation, and self-hosted extended-test workflow support.
- Updated the recurring release checklist in root `todo.md` so the extended `Static,Runtime,AuditSmoke` wrapper gate and compatibility-audit smoke paths are listed beside the lower-level validation commands.
- Added a changelog line for the final documentation synchronization pass.

Commands:

```powershell
rg -n "extended audit|compatibility-audit|Invoke-MIRExtendedTests|RunManualScenarios|sharded|profile-stub|profile stub|top-25|downloads_count|self-hosted|compat-failures|profile-candidates" README.md changelog.txt todo.md docs\compatibility.md docs\architecture.md docs\roadmap.md docs\notes\manual-test-plan.md docs\notes\release-plan-2.1.0.md docs\notes\release-notes-2.1.0.md docs\notes\mod-portal-page.md docs\test-results.md
rg -n "not yet|missing|blocker|do not publish|release blocker|stale|TODO|FIXME|TBD|BROKEN" README.md changelog.txt todo.md docs\compatibility.md docs\architecture.md docs\roadmap.md docs\notes\manual-test-plan.md docs\notes\release-plan-2.1.0.md docs\notes\release-notes-2.1.0.md docs\notes\mod-portal-page.md docs\test-results.md
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Test-MIRBranchPolicy.ps1
git diff --check
```

Results:

- Documentation scan found the extended audit automation described across the authoritative and derivative release docs.
- Stale-wording scan found only expected historical changelog/test-result entries, durable future-work TODOs, and documented manual-validation items.
- Package rebuild, static validation, branch-policy validation, and whitespace validation passed.

## 2026-07-04 Extended Compatibility Automation

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.
- Factorio runtime binary: `C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe`.

Scope:

- Added executable manual-scenario support to the compatibility audit harness.
- Added sharded and resumed audit support with `-FromLockfile`, `-StartIndex`, `-Count`, and `-CandidateNames`.
- Added grouped audit result conversion that writes `compat-summary.md`, `compat-failures.grouped.json`, and `profile-candidates.json`.
- Added review-only profile-stub generation from grouped failures.
- Added `Invoke-MIRExtendedTests.ps1` as the tiered wrapper for static, runtime, smoke, top-25, manual-scenario, full-audit, and save-compat tiers.
- Added a self-hosted GitHub workflow for unattended extended audits.
- Updated README, architecture, compatibility, roadmap, manual-test, release-plan, TODO, and changelog docs.

Commands:

```powershell
.\scripts\Invoke-MIRExtendedTests.ps1 -Tier Static,Runtime,AuditSmoke -FactorioBin 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe' -OutputRoot .\build\extended-final -FailFast
.\scripts\Invoke-MIRCompatAudit.ps1 -MaxCandidates 0 -CatalogPages 0 -RunManualScenarios -ScenarioNames space-age-baseline -OutputDir .\build\compat-manual-smoke
.\scripts\Convert-MIRCompatAuditResults.ps1 -AuditDir .\build\compat-manual-smoke
.\scripts\Invoke-MIRExtendedTests.ps1 -Tier AuditSmoke -OutputRoot .\build\extended-smoke -FailFast
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRCompatAudit.ps1 -FromLockfile .\build\extended-smoke\audit-smoke\compat-candidates.lock.json -StartIndex 0 -Count 1 -OutputDir .\build\compat-lockfile-smoke
.\scripts\Convert-MIRCompatAuditResults.ps1 -AuditDir .\build\compat-lockfile-smoke
.\scripts\Invoke-MIRCompatAudit.ps1 -CandidateNames definitely-no-such-mod-mir-test -MaxCandidates 0 -CatalogPages 0 -OutputDir .\build\compat-stub-smoke
.\scripts\Convert-MIRCompatAuditResults.ps1 -AuditDir .\build\compat-stub-smoke
.\scripts\New-MIRCompatProfileStub.ps1 -GroupedFailures .\build\compat-stub-smoke\compat-failures.grouped.json -GroupId FG0001
```

Results:

- Extended final wrapper gate passed for `Static`, `Runtime`, and `AuditSmoke`.
- Runtime fixture validation passed with the local Factorio binary after the automation/doc updates.
- Manual-scenario metadata smoke passed and wrote stable report, lockfile, grouped-failure, and profile-candidate artifacts.
- Extended `AuditSmoke` passed through the new wrapper and grouped converter.
- Static validation passed, including the new compatibility automation wiring check.
- Lockfile resume/sharding smoke passed from the generated audit-smoke lockfile.
- Profile-stub smoke passed and generated a review-required Lua stub under ignored build output.
- Full credentialed top-25, manual modpack load tests, and full `>=10K` audits remain future local/self-hosted runs because they require Mod Portal credentials and a Factorio binary.

## 2026-07-03 Final 2.1.0 Release Candidate Documentation Pass

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.
- Factorio runtime binary: `C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe`.

Scope:

- Audited release-candidate docs for stale publish-blocker wording after the final compatibility hardening and science-pack balance pass.
- Swapped Cargo bay unloading distance to the `landing-pad-unloading-bay` technology icon and Cargo landing pad count to the `space-platform` technology icon.
- Marked the completed runtime validation gates in root `todo.md` while keeping the top-25 real Mod Portal audit and manual save soak as future work.
- Updated `docs/roadmap.md`, `docs/notes/release-plan-2.1.0.md`, `docs/architecture.md`, `docs/api-proof-points.md`, and `docs/notes/manual-test-plan.md` so the release-candidate narrative matches the current implementation and validation state.
- Rebuilt `dist/more-infinite-research_2.1.0.zip` from the final documentation tree.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'
.\scripts\Invoke-MIRCompatAudit.ps1 -CatalogPages 1 -MaxCandidates 1 -MinDownloads 10000 -FactorioVersions '2.1' -OutputDir .\build\compat-audit-smoke
git diff --check
```

Results:

- Package build passed and refreshed `dist/more-infinite-research_2.1.0.zip`.
- Full runtime validation passed with the local Factorio binary.
- Runtime validation covered the base and Space Age fixture matrix, including generation integrity, science-pack ingredient policies, scripted enable/disable routing, fluid-output productivity, pipeline extent scaling, Plates n Circuit replacement safety, vanilla productivity-family adoption and signature refresh, weapon-speed overlap safety, Omega drill productivity, cargo logistics shape/diagnostics/icon sources, and end-game prerequisite gating.
- Compatibility audit smoke passed and wrote ignored sample output under `build/compat-audit-smoke`.
- `git diff --check` passed.
- Git reported line-ending normalization warnings only.

## 2026-07-03 Rocket/Cannon Defaults Science Pack Alignment

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.

Scope:

- Aligned `defaults.lua` fallback science-pack lists for Rocket shooting speed and Cannon shooting speed with the direct-effect stream definitions, using `electromagnetic-science-pack` instead of `agricultural-science-pack`.
- Added static validation so those two defaults must include electromagnetic science and must not include agricultural science.

Commands:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

Results:

- Static validation passed.
- Git reported line-ending normalization warnings only.

## 2026-07-03 Competitor Replacement And Audit Harness Hardening

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.
- Factorio runtime binary: `C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe`.

Scope:

- Anchored the Plates n Circuit known-competitor technology patterns to exact technology names.
- Changed known competitor replacement coverage from recipe-name-only to recipe plus productivity `change`.
- Required competitor preparation to skip candidates when another external infinite productivity owner blocks one of the candidate recipes.
- Required competitor preparation to count only streams that can produce a lab-compatible MIR replacement technology.
- Changed cleanup so a known competitor is removed only when generated MIR effects prove the same recipe and the same productivity `change`.
- Passed configured vanilla-family adoption targets into owner classification so diagnostics identify configured adoption owners instead of classifying those exact owners as unknown external techs.
- Updated the Mod Portal audit harness to exclude official built-in mods from download dependency resolution, enable required dependency closure mods in load-test `mod-list.json`, enable official built-ins when required or when `-IncludeSpaceAge` is set, copy only scenario-specific cached zips, verify cached/downloaded zip SHA1 values, force MIR generation diagnostics in copied audit runs, and return parsed audit rows in load results.

Commands:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'
```

Results:

- Static validation passed.
- Full runtime validation passed.
- The existing full-replacement Plates n Circuit fixture still prepared and removed the fully covered competing plate/circuit technologies.
- The existing partial-coverage fixture still kept the combined plate competitor when an enabled MIR stream could not cover every effect.
- Added and passed a productivity-change mismatch fixture proving MIR keeps `electric-circuit-productivity` when the competitor effect is `0.05` and MIR would generate `0.10`.
- Added and passed a blocked-owner fixture proving MIR does not prepare a combined plate competitor when another external owner also owns copper plate, preventing a duplicate MIR iron owner while the combined competitor remains.
- Git reported line-ending normalization warnings only.

## 2026-07-03 Release Candidate Science Pack Rebalance

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.
- Factorio runtime binary: `C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe`.

Scope:

- Added space science to Spoilage preservation.
- Added space science to Artificial soil productivity alongside agricultural science.
- Replaced agricultural science with electromagnetic science for Rocket shooting speed and Cannon shooting speed.
- Changed fluid productivity extra packs: Oil processing uses cryogenic science, Oil cracking uses agricultural science, Lubricant uses electromagnetic science, and Sulfuric acid uses metallurgic science.
- Added electromagnetic and cryogenic science to Agricultural growth speed alongside agricultural science.
- Added cryogenic science to Bacteria cultivation productivity and Breeding productivity alongside agricultural science.
- Added validation helpers that inspect only the generated report `science=` field so science-pack replacement assertions are not confused by prerequisite fields.

Commands:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'
```

Results:

- Full runtime validation passed.
- The Space Age scripted-candidate scenario now asserts Spoilage preservation includes `space-science-pack`, and Agricultural growth speed includes `agricultural-science-pack`, `electromagnetic-science-pack`, and `cryogenic-science-pack`.
- The Space Age generation-integrity scenario now asserts Artificial soil productivity includes agricultural and space science, Bacteria cultivation and Breeding include agricultural and cryogenic science, and Rocket/Cannon shooting speed include electromagnetic science without agricultural science.
- The Space Age fluid-productivity scenario now asserts Oil processing, Oil cracking, Lubricant, and Sulfuric acid productivity use cryogenic, agricultural, electromagnetic, and metallurgic science respectively, without retaining `space-science-pack` in their `science=` fields.
- Git reported line-ending normalization warnings only.

## 2026-07-03 Runtime Validation After Compatibility Refactor

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.
- Factorio runtime binary: `C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe`.

Scope:

- Ran the full runtime validation harness after the compatibility architecture refactor, Space Age productivity stream split, bacteria cultivation productivity addition, carbon lower-tier recipe additions, docs planning update, and rebuilt package.
- Fixed the runtime fixture enumerator so `fixtures/compat-matrix` is treated as audit input data instead of a loadable fixture mod, matching the existing static fixture skip policy.

Commands:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRCompatAudit.ps1 -CatalogPages 1 -MaxCandidates 1 -MinDownloads 10000 -FactorioVersions '2.1' -OutputDir .\build\compat-audit-smoke
git diff --check
```

Results:

- First runtime attempt correctly exposed a validation-harness bug: `fixtures/compat-matrix` has no `info.json` because it is audit matrix input data, not a fixture mod.
- Updated `scripts/Invoke-MIRValidation.ps1` so the runtime fixture collector skips `compat-matrix`.
- Full runtime validation then passed with the local Factorio binary.
- Runtime scenarios covered base and Space Age load checks, lab reduce/skip policy, science-pack ingredient policies, scripted candidate enable/disable routing, base/Space Age generation integrity, fluid productivity, pipeline extent scaling, Plates n Circuit replacement/partial coverage, vanilla productivity-family adoption and signature-change refresh, weapon-speed overlap safety, Omega drill productivity, cargo logistics shape/diagnostics, and end-game prerequisite gating.
- Runtime validation logged the expected productivity-family signature reset during the configuration-change fixture scenario.
- Runtime validation logged the expected Plates n Circuit competing technology preparation/removal during the full-replacement fixture scenario.
- Runtime validation logged the expected partial-coverage skip behavior when MIR could not replace every competing technology effect.
- Git reported line-ending normalization warnings only.

## 2026-07-03 Space Age Productivity Stream Split

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.
- Factorio runtime binary: not configured in this shell; runtime fixture validation was not run in this pass.

Scope:

- Replaced the broad Stone product productivity stream with separate Landfill productivity, Artificial soil productivity, and Molten metals productivity streams.
- Added a lower-tier lithium-from-brine recipe bucket to Lithium productivity.
- Added Carbon productivity and Ice productivity streams for Space Age asteroid-crushing/output recipes and compatible modded outputs.
- Added lower-tier Carbon productivity coverage for burnt spoilage and coal synthesis.
- Added Bacteria cultivation productivity for Space Age iron and copper bacteria cultivation recipes.
- Added a `2.1.0` JSON migration from the retired Stone product productivity generated technology ID to the new Landfill productivity generated technology ID.
- Updated locale, README, changelog, mod-portal notes, release notes, and compatibility documentation to match the split.
- Rebuilt the release archive after the stream split.

Commands:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Build-MIRPackage.ps1
```

Results:

- Static/package validation passed.
- Locale parity passed for all 9 locale files.
- The rebuilt release archive contains `migrations/more-infinite-research_2.1.0.json`, updated `prototypes/streams/productivity.lua`, and updated `docs/notes/release-notes-2.1.0.md`.
- Runtime Factorio load validation was skipped because `FACTORIO_BIN` is not configured.
- Git reported line-ending normalization warnings only.

## 2026-07-03 Documentation Reorganization And Package Refresh

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.
- Factorio runtime binary: not configured in this shell; runtime fixture validation was not run in this pass.

Scope:

- Accepted the documentation hierarchy reorganization.
- Moved the executable future-work ledger to root `todo.md`.
- Kept `changelog.txt` as the durable past-change ledger.
- Kept `docs/roadmap.md` as the high-level rationale and release narrative.
- Kept derivative/supporting plans, release notes, mod-portal copy, and manual plan under `docs/notes/`.
- Updated README, roadmap, architecture, compatibility, manual-plan links, changelog, build packaging, and validation to match the new hierarchy.
- Rebuilt the release archive after the compatibility architecture refactor and documentation reorganization.

Commands:

```powershell
git fetch origin dev
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRCompatAudit.ps1 -CatalogPages 1 -MaxCandidates 1 -MinDownloads 10000 -FactorioVersions '2.1' -OutputDir .\build\compat-audit-smoke
git diff --check
```

Results:

- `origin/dev` fetched successfully before commit prep.
- Static/package validation passed with root `todo.md` included in the package contract.
- `dist/more-infinite-research_2.1.0.zip` was rebuilt.
- The rebuilt release archive contains root `todo.md` and the reorganized `docs/notes/` tree.
- Compatibility-audit smoke passed and wrote ignored sample output under `build/compat-audit-smoke`.
- The smoke selected no locked mods because the sampled portal candidate did not have a compatible Factorio `2.1` release; the report correctly recorded the release-selection failure.
- `git diff --check` passed. Git reported line-ending normalization warnings only.

## 2026-07-03 Compatibility Architecture Refactor

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.
- Factorio runtime binary: not configured in this shell; runtime fixture validation was not run in this pass.

Scope:

- Refactored recipe-productivity owner classification into `prototypes/compat/productivity-owners.lua`.
- Moved data-stage productivity-family adoption into `prototypes/compat/productivity-family-adoption.lua`.
- Made known competing recipe-productivity technology patterns profile-driven through `prototypes/compat/profiles.lua`.
- Added parser-friendly audit rows to generation diagnostics.
- Added the local mod-portal compatibility audit harness and committed compatibility-matrix inputs.

Commands:

```powershell
.\scripts\Invoke-MIRCompatAudit.ps1 -CatalogPages 1 -MaxCandidates 1 -MinDownloads 10000 -FactorioVersions '2.1' -OutputDir .\build\compat-audit-smoke
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
git diff --check
```

Results:

- Compatibility-audit smoke passed and wrote ignored sample output under `build/compat-audit-smoke`.
- The smoke selected no locked mods because the first sampled catalog candidate did not have a compatible Factorio `2.1` release; the report correctly recorded the release-selection failure.
- Static/package validation passed and rebuilt `build/validation-dist/more-infinite-research_2.1.0.zip`.
- `git diff --check` passed. Git reported line-ending normalization warnings only.

## 2026-07-03 2.1.0 Release Candidate Audit

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.
- Installed local Factorio binary: `2.1.9` build `86829`, Windows Steam.
- Release archive rebuilt: `dist/more-infinite-research_2.1.0.zip`.
- Validation archive rebuilt: `build/validation-dist/more-infinite-research_2.1.0.zip`.

Scope:

- Reviewed the full delta from tag `2.0.5` through the current `dev` head.
- Refreshed release docs, TODO, roadmap, compatibility notes, manual test plan, API proof ledger, release notes, and mod portal copy for the actual `2.1.0` release-candidate scope.
- Confirmed there is no MIR steel-plate productivity stream, so steel-family adoption remains intentionally absent.
- Confirmed the broad native modifier skip/warn/prefer/allow policy, high-throughput pump, existing agricultural plant rescale, and stronger scripted spoilage/agriculture claims are deferred.
- Confirmed shipped compatibility scope is targeted: exact recipe-productivity owner filtering, vanilla Space Age family adoption, and known fully covered recipe-productivity competitor replacement.
- Loaded the rebuilt release zip itself from isolated normal mod directories in base-only and Space Age save-creation smokes.

Commands:

```powershell
& "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe" --version
rg "data.raw.tool|tool_exists|has_tool|PACKS_ALL" prototypes
rg "on_tick|on_nth_tick" control prototypes
rg "icon_mipmaps" prototypes
.\scripts\Build-MIRPackage.ps1
.\scripts\Test-MIRLocales.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
.\scripts\Test-MIRBranchPolicy.ps1
git diff --check

# Release-zip smoke:
# Copy dist/more-infinite-research_2.1.0.zip into isolated base-only and Space Age temp mod directories,
# write matching mod-list.json files, and run Factorio --create for each scenario.
```

Results:

- Factorio reported `Version: 2.1.9 (build 86829, win64, steam)`.
- Stale release-scope scans found no active contradiction after the docs update.
- Code hygiene scans found no old science-pack authority, runtime tick handlers, or generated `icon_mipmaps` usage.
- Locale validation passed across nine locale files, with only the expected missing supported-language directory warning list.
- Static/package validation passed and rebuilt the validation archive.
- Runtime fixture validation passed across the full Factorio load-test matrix.
- Plates n Circuit Productivity compatibility passed both the full replacement scenario and the partial-coverage scenario.
- Vanilla Space Age productivity-family adoption passed adoption, exact-owner skip, prepatched-owner skip, mixed-owner fallback, productivity-disallowed recipe rejection, and configuration-change technology-effect refresh scenarios.
- Fluid productivity and pipeline extent fixture coverage passed, including `200%` and `50%` pipeline multiplier scenarios.
- The rebuilt release zip loaded from isolated base-only and Space Age normal mod folders and created fresh saves in both scenarios.
- Branch policy validation passed for `origin/main`, `origin/dev`, and `origin/legacy`.
- `git diff --check` passed. Git reported line-ending normalization warnings only.

## 2026-07-03 Pipeline Extent Dropdown Pass

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.
- Installed local Factorio binary: `C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe`.
- Validation archive rebuilt: `build/validation-dist/more-infinite-research_2.1.0.zip`.

Scope:

- Changed `mir-pipeline-extent-multiplier` from a freeform numeric startup setting to a fixed dropdown with `50%`, `75%`, `100%`, `125%`, `150%`, `200%`, `250%`, `300%`, `400%`, and `500%`.
- Kept the default at `100%`, which leaves fluid box prototypes unchanged and avoids loading the pipeline extent pass.
- Added shared parsing for the dropdown value so sub-`100%` choices such as `50%` are valid and still use the same prototype scaling path.
- Updated locale labels, README, changelog, release notes, compatibility docs, and validation coverage for the dropdown model.

Commands:

```powershell
.\scripts\Test-MIRLocales.ps1
git diff --check
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Locale validation passed across nine locale files.
- Static/package validation passed and rebuilt the validation archive.
- Runtime fixture validation passed across the full Factorio load-test matrix.
- The default `100%` pipeline setting remained inert during `base-generation-integrity`.
- `pipeline-extent-multiplier` proved the dropdown value `200%` parses to multiplier `2` and mutates representative pipe, pipe-to-ground, and storage-tank fluid boxes.
- `pipeline-extent-multiplier-50` proved the dropdown value `50%` parses to multiplier `0.5` and mutates the same representative fluid boxes.
- The pipeline scenarios logged `Applied pipeline extent multiplier 2 to 31 fluid boxes.` and `Applied pipeline extent multiplier 0.5 to 31 fluid boxes.`
- `git diff --check` passed.

## 2026-07-03 Unsafe Pickup Reach Guard

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.
- Installed local Factorio binary: `C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe`.
- Validation archive rebuilt: `build/validation-dist/more-infinite-research_2.1.0.zip`.

Scope:

- Added a generated-technology safety guard blocking `character-item-pickup-distance` and `character-loot-pickup-distance` effects.
- Wired the guard into generated stream technologies, copied vanilla-chain continuations, and the final registered-technology assertion pass.
- Added static validation requiring the safety guard and rejecting those effect names outside the guard module.
- Added generation-integrity fixture coverage proving loaded technologies do not carry the blocked pickup reach effects.
- Fixed the runtime validation harness so non-default pipeline extent multipliers below `100%`, such as `50%`, are actually written into copied scenario settings.

Commands:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Static/package validation passed and rebuilt the validation archive.
- Runtime fixture validation passed across the full Factorio load-test matrix.
- `base-generation-integrity` and `space-age-generation-integrity` loaded with the unsafe pickup reach exclusion fixture assertions active.
- The runtime pipeline scenarios proved both `200%` and `50%` pipeline extent multipliers are applied when explicitly set.

## 2026-07-03 Fluid Productivity Icon And Acid Neutralization Pass

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.
- Installed local Factorio binary: `C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe`.
- Validation archive rebuilt: `build/validation-dist/more-infinite-research_2.1.0.zip`.

Scope:

- Changed Oil cracking productivity to prefer the oil processing unlock technology art instead of advanced oil processing art.
- Changed Sulfuric acid productivity to prefer sulfuric acid fluid art instead of sulfur processing technology art.
- Added exact `acid-neutralisation` recipe matching to Sulfuric acid productivity when that recipe exists, while keeping `acid-neutralization` as a compatible fallback.
- Extended fluid-productivity fixture assertions so acid neutralization must have exactly one infinite productivity owner when present.
- Added runtime diagnostics assertions for the selected oil cracking and sulfuric acid icon sources in both base-only and Space Age fluid-productivity scenarios.

Commands:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
git diff --check
```

Results:

- Static/package validation passed and rebuilt the validation archive.
- Runtime fixture validation passed across the full Factorio load-test matrix.
- `base-fluid-productivity` and `space-age-fluid-productivity` proved Oil cracking productivity reports `icon=tech:oil-processing`.
- `base-fluid-productivity` and `space-age-fluid-productivity` proved Sulfuric acid productivity reports `icon=fluid:sulfuric-acid`.
- The fluid-productivity fixture proved Space Age `acid-neutralisation` is covered by Sulfuric acid productivity when the recipe exists, with no duplicate infinite productivity owner.
- `git diff --check` passed.

## 2026-07-03 Settings Enablement Simplification

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.
- Installed local Factorio binary: `C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe`.
- Validation archive rebuilt: `build/validation-dist/more-infinite-research_2.1.0.zip`.

Scope:

- Removed the planned settings mode startup setting, per-technology enable-policy settings, and preset resolver module.
- Kept per-technology enable checkboxes as the single source of truth for generated streams, base continuations, and scripted runtime effects.
- Updated locale, README, release docs, validation fixtures, and runtime scenarios to cover checkbox-enabled and checkbox-disabled behavior.

Commands:

```powershell
.\scripts\Test-MIRLocales.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
git diff --check
```

Results:

- Locale validation passed across nine locale files.
- Static/package validation passed and rebuilt the validation archive.
- Runtime fixture validation passed across the full Factorio load-test matrix.
- `checkbox-enabled-default-off-features` proved disabled-by-default stream and base-extension features generate when their checkboxes are enabled.
- `checkbox-disabled-default-on-features` proved default-enabled stream and base-extension features skip when their checkboxes are disabled.
- Scripted Space Age candidates generated and applied runtime effects when their checkboxes were enabled, and skipped with disabled runtime logs when left off.
- `git diff --check` passed.

## 2026-07-02 v2.1.0 Metadata And Package Build

Environment:

- Branch: `dev`.
- Mod version `2.1.0`.
- Release archive rebuilt: `dist/more-infinite-research_2.1.0.zip`.
- Validation archive rebuilt: `build/validation-dist/more-infinite-research_2.1.0.zip`.

Scope:

- Bumped `info.json` to `2.1.0`.
- Added the `2.1.0` changelog entry and player-facing release notes.
- Refreshed current-release README, mod portal copy, and in-game experimental setting notes.
- Built the new release archive from the current source tree.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
git diff --check
```

Results:

- Static validation passed, including metadata, locale parity, package parity, changelog format, package source/docs/locale/control/migration checks, and whitespace checks.
- Package validation built `build/validation-dist/more-infinite-research_2.1.0.zip`.
- The release zip root is `more-infinite-research_2.1.0/`.
- The packaged `info.json` reports version `2.1.0` and Factorio line `2.1`.
- Runtime validation was not run in this pass.

## 2026-07-02 Dev Fluid Productivity And Pipeline Extent Pass

Environment:

- Branch: `dev`.
- Mod version `2.0.5` source line, preparing `v2.1.0` fluid and prototype-setting changes.
- Installed local Factorio binary: `2.1.9` build `86829`, Windows Steam.
- Validation archive rebuilt: `build/validation-dist/more-infinite-research_2.0.5.zip`.

Scope:

- Added fluid-output recipe-productivity streams for oil processing, oil cracking, lubricant, sulfuric acid, Space Age thruster fuel, and Space Age thruster oxidizer.
- Added fluid prototype lookup, fluid-output recipe matching, fluid icon fallback, and required-fluid stream gates.
- Added `mir-pipeline-extent-multiplier`, a startup-only setting whose default `1x` leaves fluid boxes unchanged and does not load the pipeline prototype pass.
- Added post-MIR assertion fixtures for fluid-productivity ownership and explicit pipeline extent scaling.

Commands:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
git diff --check
```

Results:

- Static validation passed, including locale parity, snippet coverage, package metadata/parity, and whitespace checks.
- Runtime fixture validation passed on Factorio `2.1.9`.
- `base-generation-integrity` proved the default `1x` pipeline setting does not log or run the pipeline extent pass.
- `base-fluid-productivity` proved base oil processing, oil cracking, lubricant, and sulfuric acid streams generate and that thruster streams skip cleanly without Space Age fluids.
- `space-age-fluid-productivity` proved Space Age thruster fuel and thruster oxidizer streams generate with two recipe effects each, alongside the base fluid-output streams.
- `pipeline-extent-multiplier` proved `mir-pipeline-extent-multiplier = 2` applies during startup prototype load and mutates representative pipe, pipe-to-ground, and storage-tank fluid boxes.
- The pipeline scenario logged: `Applied pipeline extent multiplier 2 to 31 fluid boxes.`

Limitations:

- Automated fixtures prove prototype load safety and exact infinite owner shape. They do not replace manual balance/soak testing in large saves or mod packs.
- The pipeline extent multiplier remains a startup setting, not research, and should stay default `1x`.

## 2026-07-02 Dev Scripted Checkbox Runtime Resolver Pass

Environment:

- Branch: `dev`.
- Mod version `2.0.5` source line, preparing `v2.1.0` scripted setting changes.
- Installed local Factorio binary: `2.1.9` build `86829`, Windows Steam.
- Release archive rebuilt: `dist/more-infinite-research_2.0.5.zip`.
- Validation archive rebuilt: `build/validation-dist/more-infinite-research_2.0.5.zip`.

Scope:

- Added `control/settings-resolver.lua` so control-stage scripted effects use
  the same effective stream enablement as data-stage technology generation.
- Spoilage preservation and agricultural growth speed now honor the same
  `ips-enable-<stream>` checkbox path used by data-stage stream generation.
- Added scripted diagnostic log lines that expose effective runtime enablement
  without adding tick handlers, broad entity scans, or inventory/item-stack
  scans.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Static validation passed, including control resolver snippets, control effect
  wiring, locale parity, no-runtime-tick guard, package metadata, and changelog
  format checks.
- Runtime fixture validation passed on Factorio `2.1.9`.
- `space-age-scripted-candidates-enabled` proved checkbox-enabled scripted
  streams both generate and log enabled runtime recomputation.
- `space-age-scripted-candidates-disabled` proved default-disabled scripted
  streams skip generation and log disabled runtime recomputation.

Limitations:

- These fixtures prove setting routing, not measured gameplay
  behavior in real saves.
- Existing spoilable stack behavior, research reversal, disabling after use,
  multi-force spoilage behavior, and real agricultural tower planting remain
  manual proof gates before default enablement or stronger public claims.

## 2026-07-02 Dev Settings Enablement Experiment

Environment:

- Branch: `dev`.
- Mod version `2.0.5` source line, preparing `v2.1.0` settings changes.
- Installed local Factorio binary: `2.1.9` build `86829`, Windows Steam.
- Release archive rebuilt: `dist/more-infinite-research_2.0.5.zip`.
- Validation archive rebuilt: `build/validation-dist/more-infinite-research_2.0.5.zip`.

Scope:

- Tried a startup settings-mode experiment for technology enablement.
- The experiment was removed before release because it added per-technology
  override UI without solving settings sharing.
- Cost, growth, maximum level, and research unit time remain the existing
  manual tunables.
- Routed generated streams, base-technology continuations, and competing
  base-extension cleanup through the shared settings resolver.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
.\scripts\Test-MIRBranchPolicy.ps1
git diff --check
```

Results:

- Static validation passed, including setting resolver snippets, locale parity,
  no-runtime-tick guard, package metadata, and changelog format checks.
- Runtime fixture validation passed on Factorio `2.1.9`.
- `checkbox-enabled-default-off-features` proved disabled-by-default streams and
  continuations generate when their checkboxes are enabled.
- `checkbox-disabled-default-on-features` proved default-enabled streams and
  continuations skip when their checkboxes are disabled.
- The generation-integrity fixture was updated to assert effective base
  continuation enablement through the shared resolver.
- Branch policy validation and `git diff --check` passed.

Limitations:

- No shareable settings-profile flow is implemented in this release.
- The visible checkbox behavior is the source of truth.
- Scripted spoilage/agriculture behavior still needs the manual save matrix
  before default enablement or stronger measured gameplay claims.

## 2026-07-02 Dev Installed Space Age Icon Opt-In Pass

Environment:

- Branch: `dev`.
- Mod version `2.0.5` source line, preparing `v2.1.0` changes.
- Installed local Factorio binary: `2.1.9` build `86829`, Windows Steam.
- Space Age files were installed locally.
- Release archive rebuilt: `dist/more-infinite-research_2.0.5.zip`.
- Validation archive rebuilt: `build/validation-dist/more-infinite-research_2.0.5.zip`.

Probe:

- A temporary probe mod outside the repository loaded a technology icon from
  `__space-age__/graphics/technology/electric-weapons-damage.png` while
  `space-age` was installed but disabled in the test mod list.
- The probe reached save creation successfully with only `base` and the probe
  mod active.
- This proves direct asset paths can resolve on this local install, but it does
  not provide a safe data-stage way to detect that another player's Space Age
  files are installed.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
.\scripts\Test-MIRBranchPolicy.ps1
git diff --check
```

Results:

- Added `mir-use-installed-space-age-icons`, a default-off startup setting for
  base-game runs where Space Age is installed locally but disabled.
- Added `inactive_mod_asset = "space-age"` icon candidates for selected streams
  so the resolver can reference direct `__space-age__` icon paths only when
  Space Age is loaded or the new opt-in setting is enabled.
- Default base-only runtime fixtures still reject generated icon layers that
  resolve to `__space-age__` paths.
- The new `base-installed-space-age-icon-assets` runtime fixture enables the
  opt-in setting while Space Age is disabled and asserts Electric Shooting Speed
  and Research productivity resolve to the expected direct Space Age icon paths.
- Space Age runtime fixtures still prefer loaded Space Age prototype art.
- Static/package validation, runtime fixture validation, branch policy
  validation, and `git diff --check` passed.

Limitations:

- The setting must stay disabled by default. If a player enables it without
  Space Age files installed, Factorio can fail during prototype loading before
  MIR can recover.
- MIR still does not package or redistribute Space Age PNG assets.

## 2026-07-02 Dev Icon Candidate Resolver Pass

Environment:

- Branch: `dev`.
- Mod version `2.0.5` source line, preparing `v2.1.0` changes.
- Installed local Factorio binary: `2.1.9` build `86829`, Windows Steam.
- Release archive rebuilt: `dist/more-infinite-research_2.0.5.zip`.
- Validation archive rebuilt: `build/validation-dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
.\scripts\Test-MIRBranchPolicy.ps1
git diff --check
```

Results:

- Added explicit ordered `icon_candidates` support to the shared technology icon resolver.
- Kept legacy `icon_tech`, `icon_techs`, `icon_item`, explicit `icon`, and explicit `icons` behavior working as fallback paths.
- Generation diagnostics now report the selected icon source through the shared resolver.
- Electric Shooting Speed, Research productivity, Processing Unit productivity, and Science pack productivity now use explicit candidate chains for Space Age/base fallback art.
- Base-only runtime fixtures assert generated technologies do not resolve icon layers to `__space-age__` paths.
- Space Age runtime fixtures assert Electric Shooting Speed still borrows `electric-weapons-damage-1` art when Space Age is loaded.
- Added `docs/asset-sources.md` and static validation requiring local image assets to have source notes while rejecting Space Age-looking local image paths.
- Static/package validation, runtime fixture validation, branch policy validation, and `git diff --check` passed.

## 2026-07-02 Dev Factorio 2.1.9 Runtime Fixture Pass

Environment:

- Branch: `dev`.
- Mod version `2.0.5`.
- Current-line Factorio target in `info.json`: `2.1`.
- Installed local Factorio binary: `2.1.9` build `86829`, Windows Steam.
- Release archive rebuilt: `dist/more-infinite-research_2.0.5.zip`.
- Validation archive rebuilt: `build/validation-dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
& "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe" --version
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
.\scripts\Test-MIRBranchPolicy.ps1
git diff --check
```

Results:

- Factorio reported `Version: 2.1.9 (build 86829, win64, steam)`.
- Static/package validation passed.
- Runtime fixture validation passed against Factorio `2.1.9`.
- The current-line Factorio `2.1` cargo fixture scenarios ran instead of being skipped.
- Branch policy validation passed for `origin/main`, `origin/dev`, and `origin/legacy`.
- `git diff --check` passed; Git reported line-ending normalization warnings only.
- This pass resolves the earlier `dev` note that runtime validation still needed to be rerun after the local install returned to Factorio `2.1.x`.

## 2026-07-02 Dev Post-Legacy Reconciliation Pass

Environment:

- Branch: `dev`.
- Mod version `2.0.5`.
- Current-line Factorio target in `info.json`: `2.1`.
- Installed local Factorio binary during this pass: `2.0.77`, so dev runtime validation was not run.
- Validation archive: `build/validation-dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Test-MIRBranchPolicy.ps1
git diff --check
```

Results:

- Reconciled current-line docs after the published `1.9.0` legacy release.
- Added `docs/release-notes-1.9.0.md` to keep the legacy release notes visible from the current development line.
- Updated README, compatibility, roadmap, and TODO language so `1.9.0` is recorded as released from `legacy`, not still planned.
- Ported the legacy-proven fixture metadata guard into `dev`: fixture `factorio_version` and `base >=` dependency floors must match the active branch line.
- Normalized dev fixture metadata so every local fixture targets Factorio `2.1` with `base >= 2.1.8`.
- Static/package validation passed and generated `build/validation-dist/more-infinite-research_2.0.5.zip`.
- Branch policy validation passed for `origin/main`, `origin/dev`, and `origin/legacy`.
- `git diff --check` passed; Git reported line-ending normalization warnings only.
- Runtime validation should be rerun after the local Factorio install is back on a Factorio `2.1.x` build.

## 2026-07-02 v2.1.0 Release-Gate Planning Pass

Environment:

- Branch: `dev`.
- Mod version `2.0.5`.
- Planning/docs-only change for the next Factorio `2.1` feature wave.
- Local Factorio binary remained `2.0.77`, so runtime validation was not run for this `dev` documentation pass.

Commands:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Test-MIRBranchPolicy.ps1
git diff --check
```

Results:

- Added `docs/release-plan-2.1.0.md` as the canonical release-gated implementation plan for `v2.1.0`.
- Tightened `v2.1.0` around settings presets, preset override behavior, native modifier overlap policy, scripted spoilage/agriculture hardening, compatibility matrix work, and proof-gated spikes.
- Added a GitHub milestone/issue checklist for the `v2.1.0` gates.
- Updated roadmap, TODO, manual test plan, compatibility docs, and README documentation map to point at the release-gated plan.
- Kept true thruster thrust research, runtime platform speed mutation, runtime quality odds mutation, refrigeration, greenhouses, super-bacteria, and broad fluid systems out of core `v2.1.0` scope.
- Static/package validation passed and generated `build/validation-dist/more-infinite-research_2.0.5.zip`.
- Branch policy validation passed for `origin/main`, `origin/dev`, and `origin/legacy`.
- `git diff --check` passed; Git reported line-ending normalization warnings only.

## 2026-07-02 Main Branch Legacy Artifact Synthesis Pass

Environment:

- Branch: `main`.
- Current-line mod version `2.0.5`.
- Added historical/canonical artifacts from the released Factorio `2.0` legacy line.
- Local Factorio binary remained `2.0.77`, so current-line runtime validation was not run.

Commands:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Test-MIRBranchPolicy.ps1
git diff --check
```

Results:

- Fast-forwarded `main` to the current `dev` documentation and validation-hardening state.
- Added `dist/more-infinite-research_1.9.0.zip` from the released `legacy` branch.
- Added a `1.9.0` changelog entry to the canonical current-line changelog so future current-line packages retain the legacy release history.
- Kept legacy-only Factorio `2.0` source changes out of `main`: `info.json` remains Factorio `2.1`, cargo logistics streams remain current-line features, and local fixtures remain Factorio `2.1` fixtures.
- Static/package validation passed and generated `build/validation-dist/more-infinite-research_2.0.5.zip`.
- Branch policy validation passed for `origin/main`, `origin/dev`, and `origin/legacy`.
- `git diff --check` passed; Git reported line-ending normalization warnings only.

## 2026-07-02 Generated Package Validation Pass

Environment:

- Mod version `2.0.5`.
- Validation archive: `build/validation-dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Test-MIRBranchPolicy.ps1
git diff --check
```

Results:

- Fixed the CI failure where README-only changes failed static validation because the committed `dist/` zip was intentionally not rebuilt.
- Static validation now builds an ignored validation archive from the current source tree before package metadata and package parity checks.
- The committed `dist/` zip remains the manual upload artifact, but normal CI no longer treats it as the live source-parity fixture for every documentation-only commit.
- Package validation still checks archive root shape, metadata, load-critical files, migrations, locale baseline, forbidden artifacts, and current source/package parity.
- Static/package validation passed.
- Branch policy validation passed for `origin/main`, `origin/dev`, and `origin/legacy`.

## 2026-07-02 Flexible Package Layout Validation Pass

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
.\scripts\Test-MIRBranchPolicy.ps1
git diff --check
```

Results:

- Removed the root `preview.png` asset from the repository.
- Relaxed package validation so documentation and helper modules are not tied to fixed historical paths.
- Package validation now keeps exact checks for load-critical Factorio entry files, locale baseline, metadata, migrations, forbidden artifacts, and archive root shape.
- Package parity now recursively follows the current source tree for packaged directories: `docs/`, `control/`, `locale/`, `migrations/`, and `prototypes/`.
- Package/source parity now compares normalized text content for text files and SHA-256 hashes for binary files, so checkout line-ending policy does not create false CI failures.
- Release documentation checks now search documentation content recursively instead of requiring specific release docs at fixed root paths.
- Temporarily moved `docs/pre-manual-2.0.5-report.md` into a nested validation-test folder, rebuilt the package, and confirmed static validation still passed while the doc was nested.
- Restored the documentation layout after the temporary move test and rebuilt the final archive.
- Static/package validation passed.
- Runtime fixture validation passed against Factorio `2.1.8`.
- Branch policy validation passed for `origin/main`, `origin/dev`, and `origin/legacy`.

## 2026-07-02 Mod Portal Documentation And Release Notes Pass

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
.\scripts\Test-MIRBranchPolicy.ps1
git diff --check
```

Results:

- Added `docs/mod-portal-page.md` as the mod-portal-ready public description.
- Added a complete player-facing technology catalog covering recipe-productivity streams, direct/scripted bonus streams, and vanilla technology continuations.
- Added `docs/release-notes-2.0.5.md` as a simplified player-facing release-note summary derived from `changelog.txt`.
- Updated the README documentation map and TODO checklist for the new public release docs.
- Rebuilt the `2.0.5` archive with the public release docs included.
- Static/package validation passed.
- Runtime fixture validation passed against Factorio `2.1.8`.
- Branch policy validation passed for `origin/main`, `origin/dev`, and `origin/legacy`.
- The remaining release gate is still manual in-game smoke testing from a normal Factorio mods folder before tagging and publishing.

## 2026-07-02 Final v2.0.5 Release-Candidate Validation

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.
- Branch before docs/package commit: `dev` at `4ec2ed6`, synced with `origin/dev`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
.\scripts\Test-MIRBranchPolicy.ps1
git diff --check
git status --short --branch
git log --oneline --decorate --graph --max-count=8
git branch -vv
rg "data.raw.tool|tool_exists|has_tool|PACKS_ALL" prototypes
rg "on_tick" control prototypes
rg "icon_mipmaps" prototypes
```

Results:

- Rebuilt `dist/more-infinite-research_2.0.5.zip` from the current source tree.
- Static/package validation passed.
- Runtime fixture validation passed against Factorio `2.1.8`.
- Branch policy validation passed for `origin/main`, `origin/dev`, and `origin/legacy`.
- Locale parity validation passed across 9 locale files.
- Package/source parity validation passed, including required `control/`, `migrations/`, `locale/`, and release documentation files.
- No-runtime-tick validation passed for `control.lua` and `control/`.
- Scripted Space Age candidate validation passed: Spoilage preservation and Agricultural growth speed remain default-off in `v2.0.5`.
- Settings confidence validation passed: generated setting names/descriptions, dropdown option descriptions, setting notes, diagnostics order, default bounds, and reader coverage are present.
- Runtime fixture coverage passed for 23 isolated scenarios: base-only generation, Space Age generation, science-pack policies, lab compatibility policies, base extension boundaries, weapon speed overlap safety, Omega Drill style recipe matching, cargo gates, cargo duplicate diagnostics, scripted candidate force-enable generation, icon source checks, icon badge checks, Space Age duplicate productivity skips, and base-game Research productivity.
- Direct release-candidate grep checks found no stale `data.raw.tool`/old science-pack authority patterns, no tick handlers, and no deprecated prototype `icon_mipmaps` usage.
- Release scan found no active `TODO`, `FIXME`, `TBD`, `BROKEN`, or stale player-facing blocker outside documented manual-validation items and historical changelog/roadmap notes.

Remaining release gate:

- Manual in-game smoke testing from a normal Factorio mods folder is still required before tagging and publishing.
- Scripted spoilage/agriculture behavior remains default-off and should not be described with stronger gameplay claims until the manual matrix records measured results.

## 2026-07-02 Base-Game Research Productivity And Icon Source Pass

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
.\scripts\Test-MIRBranchPolicy.ps1
```

Results:

- Processing Unit productivity now borrows the `processing-unit` unlock technology art, with the old `advanced-electronics-2` ID retained as an icon fallback for compatibility.
- Wall productivity now borrows the vanilla `gate` technology art.
- Rocket Fuel productivity now borrows the vanilla `rocket-fuel` unlock technology art.
- Science pack productivity now uses Space Age `research-productivity` art when available and base-game `space-science-pack` technology art otherwise.
- Added base-game Research productivity as a direct-effect stream using Factorio's native `laboratory-productivity` modifier.
- Space Age skips MIR's Research productivity stream because vanilla `research-productivity` already exists.
- Base-game Research productivity uses Military science pack technology art with MIR's productivity badge.
- Runtime fixtures assert the new icon sources, base-game Research productivity generation, Space Age duplicate prevention, and the productivity badge for the native lab-productivity stream.

## 2026-07-02 Agricultural Growth Icon And Pre-Manual Regression Pass

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
.\scripts\Test-MIRBranchPolicy.ps1
```

Results:

- Agricultural Growth Speed now borrows the vanilla Space Age `agriculture` technology art instead of the agricultural science pack item icon.
- The generated technology still receives MIR's speed badge after inherited constant badges are stripped.
- Added runtime fixture coverage that fails if Agricultural Growth Speed stops using the vanilla `agriculture` technology art.
- Static/package validation, runtime fixture validation, branch policy validation, locale parity, package parity, no-`on_tick` guard, scripted default-off guard, and generated icon badge checks passed.
- Manual gameplay validation is still required before enabling scripted streams by default or making stronger measured spoilage/agriculture behavior claims.

## 2026-07-02 Cannon Shell Productivity And Icon Badge Pass

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Renamed the player-facing `research_heavy_ammo` line to Cannon shell productivity while preserving the generated technology ID `recipe-prod-research_heavy_ammo-1`.
- Changed Cannon shell productivity to use cannon shell item art, matching the Cannon Shooting Speed base icon family.
- Kept Cannon shell productivity scoped to ammo recipes: cannon shells, artillery shell, railgun ammo, and compatible modded shell/ammo patterns.
- Left artillery turrets, artillery wagons, railgun turrets, and other machines out of this ammo tech for `v2.0.5`; those belong in a future systems/productivity decision if added.
- Updated generated stream icon construction so inherited vanilla technology constant badges are stripped before MIR applies the badge matching its actual effect.
- Added runtime fixture assertions that generated MIR stream icons have the expected effect badge and no wrong inherited constant badge.
- Runtime fixture validation passed across twenty-three isolated scenarios.

## 2026-07-01 Settings Confidence Pass

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Rebuilt the release archive after settings UI and locale changes.
- Static/package validation passed.
- Runtime fixture validation passed across twenty-three isolated scenarios.
- Locale parity validation passed across nine locale files after normalizing settings UI text to English fallback where translations are not yet refreshed.
- Added validation coverage for default-disabled-first technology setting order, diagnostics ordering, dropdown option descriptions, default-off warning notes, base-extension max-level locale wiring, and README settings guidance.
- No real settings presets were added; shareable settings profiles remain future work.

## 2026-07-01 Final Smoke Plan Guard

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Added `character-reach-icon` and `merged-inventory-trash-ui` to the canonical manual `v2.0.5` smoke plan.
- Added static validation that required final manual scenario names stay present in `docs/manual-test-plan.md`.
- Added static validation that required API proof links stay present in `docs/api-proof-points.md`, and that the API link list does not contain empty link entries.
- GitHub issue #5 was rechecked through the GitHub API and was already closed as completed.
- Static/package validation passed after rebuilding the release archive.
- Runtime fixture validation passed across twenty-three isolated scenarios.

## 2026-07-01 Electric Shooting Speed Space Age Icon

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Electric Shooting Speed now prefers the Space Age `electric-weapons-damage-1` technology icon when Space Age is active.
- Electric Shooting Speed still falls back to the base discharge defense technology icon when Space Age is absent.
- Runtime diagnostics now assert the Space Age scenario resolves `icon=tech:electric-weapons-damage-1`; the existing base/no-Space-Age scenario still asserts `icon=tech:discharge-defense-equipment`.
- Static/package validation passed after rebuilding the release archive.
- Runtime fixture validation passed across twenty-three isolated scenarios.

## 2026-07-01 Character Reach Icon

Environment:

- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Character reach bonus now uses the same base pickaxe technology icon texture as character mining speed.
- Static/package validation passed after rebuilding the release archive.
- Runtime fixture validation passed across twenty-three isolated scenarios.

## 2026-07-01 Spoilage Icon And Character Slot Merge

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Official Factorio migration and command-line docs checked on 2026-07-01.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Scripted `nothing` effects now use compact base stream icons, not full technology icon stacks with floating constant overlays.
- Character inventory slot research now grants both `character-inventory-slots-bonus` and `character-logistic-trash-slots`.
- Removed the separate generated `research_character_trash_slots` stream, setting, and current locale key.
- Added `migrations/more-infinite-research_2.0.5.json` to map `recipe-prod-research_character_trash_slots-1` into `recipe-prod-research_inventory_capacity-1` for existing saves.
- Package/build/runtime-copy validation now includes `migrations/`.
- Runtime validation now uses an isolated Factorio config and write-data/log directory, so the fixture matrix does not read the live GUI profile log.
- Added runtime scenario `character-inventory-merged-effects`, verifying `research_inventory_capacity` generates with `effects=2` and no old `research_character_trash_slots` stream diagnostics.
- Static validation passed.
- Runtime fixture validation passed across twenty-three isolated scenarios.

## 2026-07-01 Legacy Cadence Reorder

Environment:

- Mod version `2.0.5`.
- Planning/docs-only change.

Results:

- Reordered the planned Factorio `2.0.x` legacy cadence so `v1.9.0` is now a compatibility backport of the tested `v2.0.5` quick-patch snapshot.
- Kept `v2.1.0` as the next larger Factorio `2.1.x` feature wave after `v2.0.5` and `v1.9.0`.
- Kept later backport cadence as `v2.1.5 -> v1.9.5` and final `v1.9.9` from the latest tested `2.x.x` source snapshot at the verified upstream cutoff.
- Preserved the requirement that `v1.9.0` remove or guard Factorio `2.1`-only cargo modifier surfaces unless Factorio `2.0.x` validation proves support.

## 2026-07-01 Diagnostic Cargo Overlap Pull-Forward

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Added diagnostic-only native modifier overlap reporting for direct-effect streams.
- Added `mir-fixture-duplicate-cargo-tech`, a Maraxis-like Space Age fixture with infinite `cargo-landing-pad-count` and `max-cargo-bay-unloading-distance` technologies.
- Runtime fixture validation now includes `space-age-duplicate-cargo-diagnostics`.
- The duplicate cargo scenario force-enables MIR cargo landing pad count, keeps cargo bay unloading distance enabled, and verifies both generated MIR cargo technologies still load.
- The duplicate cargo scenario verifies non-blocking `native_modifier_overlap` diagnostics for both cargo native modifiers and their fixture owners.
- Static validation passed.
- Runtime fixture validation passed across twenty-two isolated scenarios.

## 2026-07-01 Pre-Manual Hardening And Harness Repair

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Official latest API docs checked on 2026-07-01: `2.1.9`.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
git diff --check
# Separately: load dist/more-infinite-research_2.0.5.zip from isolated base-only and Space Age mod folders.
```

Results:

- Added `docs/pre-manual-2.0.5-report.md` with the manual test checklist, not-ready list, and Lua API practice check.
- Static validation now requires scripted spoilage preservation and agricultural growth speed to remain default-off until manual proof is recorded.
- Runtime fixture validation now force-enables both scripted candidate streams in base-only and Space Age scenarios. Base-only must skip them for missing Space Age; Space Age must generate each with one visible `nothing` effect.
- Fixed the runtime validation harness so it copies only package/source files into isolated Factorio mod folders instead of recursively copying the entire Git repository.
- Successful runtime validation runs now clean the generated temp user-data directory.
- Spoilage preservation now resets stored `effective_level` when MIR restores or stops applying its multiplier.
- Static validation passed.
- Runtime fixture validation passed across twenty-one isolated scenarios.
- The release zip loaded from isolated base-only and Space Age mod folders and created fresh saves.
- `git diff --check` passed. Git reported line-ending normalization warnings only.
- Manual gameplay validation remains required before enabling scripted streams by default or making measured spoilage/agriculture release claims.

## 2026-07-01 Scripted Defaults And API Recheck

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Official latest API docs checked on 2026-07-01: `2.1.9`.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
git diff --check
# Separately: copy dist/more-infinite-research_2.0.5.zip into isolated temp mod folders and run
# Factorio --create once with base only and once with Space Age/official DLC enabled.
```

Results:

- Rebuilt the release archive after code and documentation changes.
- Scripted spoilage preservation and agricultural growth speed are now disabled by default for `v2.0.5`; manual save validation is required before default enablement or stronger behavior claims.
- Spoilage preservation now stores MIR's actual applied multiplier after the clamped spoil-time value is written, so baseline rebase/restore logic is based on the effective multiplier rather than the requested multiplier.
- Documented scripted runtime storage keys in `docs/architecture.md`.
- Rechecked official latest API docs and filled the API proof ledger links. Local runtime fixture validation remains on Factorio `2.1.8`.
- Static validation passed, including release metadata, hidden Quality ordering, locale parity, changelog format, package parity, required docs/control files, and the no-runtime-tick guard.
- Runtime fixture validation passed across nineteen isolated scenarios.
- The release zip loaded from isolated normal mod folders in both base-only and Space Age modes and created fresh saves.
- `git diff --check` passed. Git reported line-ending normalization warnings only.
- Manual gameplay validation is still not complete for spoilage existing stacks, spoilage reversal/disable behavior, multi-force behavior, normal UI save checks, and large Gleba farms.

## 2026-07-01 Generated Chain Integrity

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Replaced narrow processing-unit-only assertions with `mir-fixture-assert-generation-integrity`.
- Runtime fixture validation passed across nineteen isolated scenarios, including `base-generation-integrity`, `base-generation-integrity-inserter-enabled`, `space-age-generation-integrity`, and `space-age-generation-integrity-inserter-enabled`.
- The broad fixture verified every generated `recipe-prod-*` technology is an infinite upgrade with effects and a count formula.
- The broad fixture verified default-enabled vanilla numbered extension chains have exactly one infinite serial continuation in both base-only and Space Age runs.
- The broad fixture verified the normally disabled `inserter-capacity-bonus` chain stays absent by default and generates exactly one serial continuation when force-enabled in both base-only and Space Age runs.
- The broad fixture verified every recipe has at most one infinite recipe-productivity owner.
- Circuit productivity ownership is now checked by recipe ID: base-only green/red/blue circuit recipes are MIR-owned, while Space Age green/red circuits remain MIR-owned and processing-unit productivity remains vanilla-owned.
- Space Age vanilla productivity ownership remained authoritative for processing units, low density structures, plastic, and rocket fuel recipes.
- Static validation now rejects incomplete local fixture directories before runtime fixture validation starts.

## 2026-07-01 Weapon Speed Safety And Quality Enrichment Triage

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
git diff --check
```

Results:

- Narrowed weapon shooting speed overlap adjustment so it only strips `rocket` and `cannon-shell` from MIR's generated `weapon-shooting-speed` continuation, not finite vanilla weapon shooting speed technologies.
- Added `mir-fixture-assert-weapon-speed-safety`, which failed the load if finite vanilla `weapon-shooting-speed-5` or `weapon-shooting-speed-6` lost `cannon-shell` effects under the overlap setting.
- Runtime fixture validation passed across fifteen isolated scenarios, including the new `weapon-speed-overlap-safety` scenario.
- Documented quality module enrichment as a future spike/add-on candidate, not a `v2.0.5` quick patch. The local Quality prototypes store module quality chance in `effect.quality`, and the official modifier list does not expose a native technology modifier for increasing module quality chance.
- Rebuilt the release archive after code, fixture, locale, and docs updates.

## 2026-07-01 GitHub Issue Fix Pass

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
git diff --check
```

Results:

- Fixed GitHub issue #3 coverage: electric shooting speed now uses the vanilla discharge defense technology as its icon/prerequisite anchor when Space Age is absent, and MIR supplies missing flamethrower/electric/Tesla shooting-speed descriptions.
- Fixed GitHub issue #4 coverage: mining drill productivity now matches Omega Drill style `omega-drill` and `omega-tau` recipes plus broader visible modded `*-mining-drill` / `*-drill` outputs in the high-tier bucket.
- Fixed GitHub issue #5 coverage: `info.json` now declares Quality as a hidden optional dependency, so module productivity generation sees quality module recipes when Quality is active.
- Static/package validation passed, including hidden Quality dependency policy, locale parity across 9 locale files, science-pack wiring, package metadata, and `git diff --check`.
- Runtime fixture validation passed across fourteen isolated scenarios, including the new `omega-drill-productivity` scenario.
- Runtime assertions verified base/no-Space-Age electric shooting speed generates with one `electric` effect and the discharge defense icon, base flamethrower shooting speed generates, and Space Age electric shooting speed generates with both `electric` and `tesla` effects.
- The Omega Drill assertion fixture verified `omega-drill` and `omega-tau` recipe productivity effects after MIR generation; the diagnostics row for `research_mining_drill` reported the expanded effect count.
- Manual UI validation is still recommended for the base-only `vanilla-locale-icons`, real `quality-module-productivity`, and real Omega Drill `omega-drill-productivity` scenarios before publishing the final mod-portal build.

## 2026-07-01 Release Cadence Correction

Environment:

- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
git diff --check
```

Results:

- Updated the docs back to the intended cadence: `v2.0.5` is the quick feedback patch for easy validated changes, `v2.1.0` is the larger feature wave, `v1.9.0` is backported from `v2.1.0`, `v2.1.5` can backport to `v1.9.5`, and `v1.9.9` is reserved as the final planned Factorio `2.0` port from the latest tested `2.x.x` snapshot at the Factorio `2.1` stable cutoff target.
- Rebuilt the `2.0.5` release archive after README, roadmap, TODO, compatibility, API proof, manual-test, post-2.0 planning, changelog, and test-results updates.
- Static validation passed with package/source/docs parity.
- `git diff --check` passed.
- Runtime validation was not rerun for this correction because the changes were documentation, changelog, and rebuilt-package parity only.

## 2026-07-01 Release Cadence and Branch-Aware Validation

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
git diff --check
```

Results:

- Rebuilt the `2.0.5` release archive after README/docs updates for the release cadence: `v2.0.5` quick feedback patch, `v2.1.0` larger feature wave, `v2.1.0 -> v1.9.0` first legacy port, later `v2.1.5 -> v1.9.5`, and final `v1.9.9` legacy port from the latest tested `2.x.x` snapshot.
- Static validation passed with the new branch-aware metadata check.
- Static validation passed with the new no-`on_tick` control-stage guard.
- Package validation now requires `docs/api-proof-points.md` and `docs/manual-test-plan.md`.
- Static validation now reads `info.json` to distinguish the normal Factorio `2.1` line from future Factorio `2.0` legacy metadata.
- On the Factorio `2.1` line, validation still requires the Space Age cargo streams and cargo modifier strings.
- For future Factorio `2.0` legacy metadata, validation rejects Factorio `2.1` dependency floors and rejects `max-cargo-bay-unloading-distance` / `cargo-landing-pad-count` direct-effect stream definitions.
- Runtime fixture validation passed on the current Factorio `2.1` line, including the existing cargo scenarios.
- Actual Factorio `2.0.x` runtime validation remains future work for the `legacy` branch port.

Representative validation harness evidence:

```text
[check] release metadata matches Factorio line
[check] control runtime avoids tick handlers
[run] Factorio load check with fixture mods (base-cargo-space-age-gate)
[run] Factorio load check with fixture mods (space-age-cargo-pad-enabled)
[run] Factorio load check with fixture mods (space-age-cargo-logistics-shape)
[ok] Validation completed.
```

## 2026-07-01 v2.0.5 Candidate Scripted-Tech Slice

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version metadata `2.0.5`; scripted runtime work is a default-off `v2.0.5` ship candidate and requires manual save validation before default enablement or stronger behavior claims.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Rebuilt the development archive with `control.lua` and `control/` included.
- Static validation passed, including release metadata policy, docs policy scan, old science-pack authority scan, icon scan, locale parity, progression-setting wiring, changelog syntax, package metadata, package source/docs/locale/control parity, and `git diff --check`.
- Runtime fixture validation passed across the existing thirteen isolated scenarios: `reduce-policy`, `skip-policy`, `space-pack-policy`, `base-space-promethium-pack-policy`, `space-age-space-pack-policy`, `space-age-space-promethium-pack-policy`, `all-official-pack-policy`, `all-pack-policy`, `base-extension-boundary-policy`, `end-game-prerequisite-gate`, `base-cargo-space-age-gate`, `space-age-cargo-pad-enabled`, and `space-age-cargo-logistics-shape`.
- The existing Space Age fixture scenarios loaded with the new scripted technology manager present.
- Space Age fixture validation now asserts that MIR skips parallel productivity streams for vanilla-owned `processing-unit-productivity`, `low-density-structure-productivity`, `plastic-bar-productivity`, and `rocket-fuel-productivity`.
- Static validation now asserts that electric shooting speed includes both the Space Age `tesla` ammo category and the older `electric` ammo category.
- Manual gameplay validation is still required before final `v2.0.5` runtime feature claims: spoilage deadline behavior, research reversal/configuration changes in a live save, multiple-force behavior, existing spoilable stacks, and agricultural tower planting on a large Gleba farm.

Representative validation harness evidence:

```text
Factorio 2.1.8 (build 86744, win64, steam, space-age)
[run] Factorio load check with fixture mods (space-age-space-pack-policy)
[run] Factorio load check with fixture mods (space-age-space-promethium-pack-policy)
[run] Factorio load check with fixture mods (space-age-cargo-pad-enabled)
[run] Factorio load check with fixture mods (space-age-cargo-logistics-shape)
[ok] Validation completed.
```

## 2026-06-30 Final 2.0.0 Mod-Page Release Prep

Environment:

- Mod version `2.0.0`.
- Release archive: `dist/more-infinite-research_2.0.0.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

Results:

- Rebuilt the `2.0.0` release archive after the final documentation and mod-page summary pass.
- Reformatted the repo README and changelog for clearer mod-page ingestion.
- Added branch-policy and contribution guidance for the permanent `main`, `dev`, and `legacy` origin branches.
- Static validation passed, including release metadata policy, docs policy scan, old science-pack authority scan, icon scan, locale parity, progression-setting wiring, changelog syntax, package metadata, package source/docs/locale parity, and `git diff --check`.
- Manually confirmed the rebuilt release archive contains no `graphics/` entries.
- Confirmed repo release docs and generated mod-page Markdown do not advertise the deferred science-pack productivity custom art.

## 2026-06-30 Progression Settings and Space Age Cargo Gate Validation

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.0`.
- Release archive: `dist/more-infinite-research_2.0.0.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Static validation passed, including release metadata policy, docs policy scan, old science-pack authority scan, icon scan, locale parity, progression-setting wiring, changelog syntax, package metadata, package source/docs/locale parity, and `git diff --check`.
- Runtime fixture validation passed across thirteen isolated scenarios: `reduce-policy`, `skip-policy`, `space-pack-policy`, `base-space-promethium-pack-policy`, `space-age-space-pack-policy`, `space-age-space-promethium-pack-policy`, `all-official-pack-policy`, `all-pack-policy`, `base-extension-boundary-policy`, `end-game-prerequisite-gate`, `base-cargo-space-age-gate`, `space-age-cargo-pad-enabled`, and `space-age-cargo-logistics-shape`.
- The default `reduce` lab policy generated science-pack productivity with the custom item-based fixture science pack included.
- Science-pack productivity used the vanilla `research-productivity` technology art.
- The forced `skip` lab policy skipped the intentionally incompatible science-pack productivity stream with `lab_status=invalid`.
- The `space` science-pack ingredient policy added `space-science-pack` in base-only and Space Age modes without adding promethium science.
- The `space-and-promethium` science-pack ingredient policy added `space-science-pack` in base-only mode and both `space-science-pack` and `promethium-science-pack` with Space Age enabled.
- The `all-official` science-pack ingredient policy added official base and Space Age packs while excluding the custom fixture science pack from both synthetic streams and MIR-created vanilla-chain extensions.
- The `all` science-pack ingredient policy added the custom fixture science pack discovered from active lab inputs to synthetic streams and MIR-created vanilla-chain extensions.
- The base-extension boundary scenario preserved an existing finite `research-speed-7` level from a fixture mod and generated MIR's infinite continuation at `research-speed-8`.
- The late-game prerequisite gate added `space-science-pack` as a prerequisite without adding it to the generated technology science ingredients.
- Forced cargo landing pad count research skipped in base-only mode with `missing required mod space-age` and generated successfully when Space Age was enabled.
- The Space Age cargo logistics shape scenario verified cargo effect types, modifier values, research times, cost formulas, prerequisites, and all-official science-pack ingredients.
- Static validation checked that cargo bay unloading distance defaults to `120` seconds, cargo landing pad count defaults to `240` seconds, both cargo streams use official science packs only, and cargo landing pad count has a modifier-description locale key.

Representative validation harness evidence:

```text
Factorio 2.1.8 (build 86744, win64, steam, space-age)
[run] Factorio load check with fixture mods (space-pack-policy)
[run] Factorio load check with fixture mods (base-space-promethium-pack-policy)
[run] Factorio load check with fixture mods (space-age-space-pack-policy)
[run] Factorio load check with fixture mods (space-age-space-promethium-pack-policy)
[run] Factorio load check with fixture mods (all-official-pack-policy)
[run] Factorio load check with fixture mods (all-pack-policy)
[run] Factorio load check with fixture mods (base-extension-boundary-policy)
[run] Factorio load check with fixture mods (end-game-prerequisite-gate)
[run] Factorio load check with fixture mods (base-cargo-space-age-gate)
[run] Factorio load check with fixture mods (space-age-cargo-pad-enabled)
[run] Factorio load check with fixture mods (space-age-cargo-logistics-shape)
[ok] Validation completed.
```

## 2026-06-30 Official DLC Split Matrix

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam install.
- Mod version `2.0.0`.
- Release archive: `dist/more-infinite-research_2.0.0.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
# For each case, run Factorio with an isolated mod directory and --dump-data.
```

Matrix cases:

- Base only.
- Elevated Rails only.
- Recycler only.
- Quality with Recycler.
- Space Age with Elevated Rails and Recycler, Quality disabled.
- Space Age with Elevated Rails, Recycler, and Quality enabled.

Results:

- Static validation passed after rebuilding the release archive.
- All official DLC matrix cases completed `--dump-data` without prototype errors or fatal log markers.
- Base-only, Elevated Rails-only, Recycler-only, and Quality-with-Recycler cases skipped absent DLC-shaped streams through `no_matching_recipes` or explicit missing prototype checks.
- Space Age without Quality loaded successfully and generated Space Age-backed streams while keeping Quality disabled.
- At the time, Science-pack productivity used `tech:research-productivity` when the Space Age technology was present and fell back to the automation science pack item icon when it was absent. This fallback was later replaced with the base-game `space-science-pack` technology art in the 2026-07-02 Base-Game Research Productivity And Icon Source Pass above.

## 2026-06-30 v2.0.0 Release-Candidate Hardening

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.0`.
- Release archive: `dist/more-infinite-research_2.0.0.zip`.

Commands:

```powershell
.\scripts\Test-MIRLocales.ps1 -AllowMissingSupportedLanguages
git diff --check
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Locale validation passed for 9 locale files.
- Static validation passed, including metadata, no compatibility-mod dependency policy, docs policy scan, no old `data.raw.tool` science-pack authority, no generated `icon_mipmaps`, changelog format, release package metadata, source-to-zip comparison, and `git diff --check`.
- Runtime fixture validation passed and created the expected save.
- Runtime diagnostics generated `research_science_pack_productivity` with `mir-fixture-science-pack` included.
- The post-MIR assertion fixture `mir-fixture-assert-science-pack-productivity` loaded successfully, proving the custom item-based science-pack recipe received a `change-recipe-productivity` effect.

Representative runtime log evidence:

```text
Factorio 2.1.8 (build 86744, win64, steam, space-age)
Loading mod more-infinite-research 2.0.0 (data-final-fixes.lua)
report kind=stream key=research_science_pack_productivity status=generated ... effects=13 lab_status=reduced ... mir-fixture-science-pack
Loading mod mir-fixture-assert-science-pack-productivity 0.1.0 (data-final-fixes.lua)
Factorio initialised
```

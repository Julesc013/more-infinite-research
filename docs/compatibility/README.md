---
title: "Compatibility and Validation"
status: current
applies_to: "3.0.0+"
audience: modpack-author
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# Compatibility and Validation

More Infinite Research's current main line targets Factorio `2.1.x` and uses a compatibility-first data-stage plus narrow control-stage model.

For compatibility planning policy, use `docs/compatibility/support-lanes.md`. It defines the role taxonomy, one-archive audit template, licensing rule, save-compatibility questions, test matrix model, and planner architecture. For tested claims and future campaign rows, use `docs/compatibility/compatibility-matrix.md`. For the post-`2.2.0` target-line versioning and backport workflow, use `docs/maintainer/backporting.md`. For the `3.0.0` compatibility compiler architecture, use `docs/architecture/compatibility-compiler-charter.md` plus the focused capability, policy, decision, manifest, claim, testing, maintainer, and ADR docs.

Release-line summary:

| MIR release | Factorio line | Scope |
| --- | --- | --- |
| `2.0.5` | `2.1.x` | quick feedback patch: small fixes, default-off scripted agriculture/spoilage candidates, docs, validation, package parity |
| `1.9.0` | `2.0.x` | compatible subset backported from the tested `2.0.5` quick-patch snapshot |
| `2.1.0` | `2.1.x` | larger feature wave: simpler settings, icon policy, fluid productivity, pipeline extent, and targeted duplicate-productivity compatibility |
| `1.9.1` | `2.0.x` | compatible subset backported from the tested `2.1.0` larger feature snapshot |
| `2.1.5` | `2.1.x` | quick feedback patch after `2.1.0` |
| `1.9.7` | `2.0.x` | superseded unless explicitly revived; older week-before-Factorio-2.1-release plan |
| `1.9.8` | `2.0.x` | superseded unless explicitly revived; older Factorio-2.1-release plan |
| `2.2.0` | `2.1.x` | compatibility planner, procedural capability diagnostics, and fixture-backed proof slices |
| `1.9.2` | `2.0.x` | planned transition backport of the tested `2.2.0` source point |
| `1.9.9` | `2.0.x` | superseded unless explicitly revived; older final Factorio 2.0 plan |
| `3.x.x` | `2.1.x` | canonical modern line starting at `3.0.0`; MIR compiler architecture |
| `2.x.x` | `2.0.x` | maintained Factorio `2.0` line starting at `2.3.0`; first post-3.0 architecture port |
| `1.9.3+` | `1.1.x` | compatibility port; `1.9.0` through `1.9.2` remain transition exceptions for Factorio `2.0` |
| `1.8.x` | `0.18.x` / `1.0.x` | `1.8.0` is the published Factorio `0.18` bridge/archive package; `1.8.1+` is the maintained Factorio `1.0` line when released |
| `1.7.x` / `1.6.x` / `1.5.x` | `0.17.x` / `0.16.x` / `0.15.x` | reduced native-infinite editions |
| `1.4.x` / `1.3.x` / `0.12.x` | `0.14.x` / `0.13.x` / `0.12.x` | archive finite-ladder reconstructions |
| `0.11.x` through `0.6.x` | `0.11.x` through `0.6.x` | museum/discovery builds |

Post-transition versioning starts after the `1.9.2` backport. From that point,
public MIR version lines encode the target Factorio generation. Lower lines do
not imply feature parity; every target-line archive must load under its matching
Factorio binary before any release candidate wording is honest.

The release goal is graceful compatibility without mod-page dependency clutter: compatible mods should work when their prototypes are visible, absent mods should be skipped cleanly, and no compatibility mod should be required for this mod to load.

The current maintainer-authorized cadence is tentative but intentional: ship
validated Factorio `2.1` current-line updates weekly through December 2026 where
safe candidates exist, then run a daily older-line backport celebration from the
week before Factorio `2.1` release through the week after it. Validation and
clear support boundaries outrank the calendar.

## Compatibility Model

- Generated technologies are created in `data-final-fixes.lua` so the mod can see most recipes, items, labs, science packs, and technologies created by other mods.
- Science packs are discovered from `data.raw.lab[*].inputs` and resolved through generic item prototype lookup.
- Science-pack productivity starts with the vanilla and Space Age target list, then appends active lab inputs so custom science packs can receive productivity effects when their recipes are visible.
- A generated technology must have at least one lab that accepts its complete science-pack set. If no lab accepts the full set, `mir-lab-incompatibility-policy` controls whether the mod tries the largest deterministic lab-compatible subset (`reduce`, default) or skips the technology (`skip`). If no subset exists, the stream is skipped and logged.
- `ips-require-space-gate` adds an end-game science unlock prerequisite only. `mir-science-pack-ingredient-policy` controls whether generated technologies keep their configured ingredients, add fixed late-game packs, infer missing official or modded progression packs from selected packs, add all official base and Space Age science packs, or add every active lab science pack including compatible modded packs.
- Recipe matching supports both `recipe.category` and Factorio 2.1 `recipe.categories`, and can match visible item or fluid recipe outputs.
- Recipe-productivity generation skips recipe effects already owned by another infinite recipe-productivity technology. In Space Age this prevents parallel MIR technologies for vanilla `processing-unit-productivity`, `low-density-structure-productivity`, `plastic-bar-productivity`, and `rocket-fuel-productivity`.
- Recipe-productivity ownership is validated by exact recipe ID, not by similar technology icons. Base-only green, red, and blue circuit recipes are MIR-owned; with Space Age enabled, green and red circuits remain MIR-owned while vanilla `processing-unit-productivity` is the single infinite owner for the `processing-unit` recipe.
- Fluid-output productivity is split by process family, not by every possible fluid name. Multi-output oil-processing recipes are owned by one oil-processing stream; cracking, lubricant, sulfuric acid and acid neutralization, and thruster propellant streams stay separate because they cover narrower conversion families.
- The pipeline extent multiplier is a strictly opt-in startup-only prototype setting. At its default `100%` value, MIR does not load the pipeline pass, scan fluid boxes, log pipeline work, or change any fluid box prototypes. Non-`100%` dropdown values scale recognized fluid box fields across prototypes, not only pipe entities, so lower or higher values are experimental for machines, tanks, thrusters, and modded prototypes that define their own fluid boxes.
- Hidden recipes and recycling recipes are skipped by default. Streams can opt in with `include_hidden` or `include_recycling`.
- Optional DLC-shaped streams declare concrete required prototypes instead of requiring a specific official mod by name.
- Cargo bay unloading distance research uses Factorio 2.1.8's `max-cargo-bay-unloading-distance` technology modifier, uses official base and Space Age science packs only, and is skipped unless Space Age is active and the `landing-pad-unloading-bay` prototypes exist.
- Cargo landing pad count research uses `cargo-landing-pad-count`, uses official base and Space Age science packs only, is enabled by default, requires the vanilla `rocket-silo` cargo landing pad unlock, and is skipped unless Space Age is active and the `cargo-landing-pad` prototype exists.
- Direct-effect diagnostics report overlapping infinite non-MIR native modifier owners, including cargo/logistics modifiers. In `v2.1.0` this broad native-modifier policy remains diagnostic-only: MIR does not skip, merge, or remove those technologies based on the overlap report.
- Spoilage preservation and agricultural growth speed are implemented in `dev` as visible `nothing` technology effects plus bounded runtime behavior through the control-stage scripted technology manager.
- Scripted runtime effects use the same effective enablement model as data-stage technology generation: the stream's `ips-enable-*` checkbox controls both generated technology creation and runtime effect activation.
- Spoilage preservation remains default-off as an opt-in experimental candidate. Agricultural growth speed is enabled by default as a special Space Age technology after validation of the agricultural tower event path, while existing planted crops are still intentionally not rescanned.
- Spoilage preservation changes the global spoil time modifier and recomputes on init, configuration change, research finish/reversal, and technology effects reset.
- Agricultural growth speed adjusts newly planted agricultural tower plants from the tower planting event and does not rescan existing farms in this first implementation slice.
- Mod-specific stream changes should live in `prototypes/mir/compatibility/profiles.lua` instead of the base stream definitions.
- Recipe-productivity ownership is classified through `prototypes/mir/index/productivity_owners.lua`, so generation, adoption, diagnostics, and known-competitor cleanup use the same owner vocabulary.
- Compatibility cleanup that removes known competing technologies also removes dangling prerequisite references from remaining technologies.
- Generic competing recipe-productivity cleanup prepares only known infinite technologies declared by active compatibility profiles whose recipe-productivity effects are all covered by enabled MIR streams with matching productivity `change` values, lab-compatible replacement science, and no other blocking external owner. MIR ignores only those prepared owners during exact-owner filtering and removes them only after generated MIR effects prove the same recipe and `change` replacement. Finite upgrade chains from other mods are left alone unless a future integration models them explicitly.
- Release metadata declares optional ordering for official DLC mods, with hidden optional ordering for Elevated Rails and Quality. Elevated Rails is hidden because its Rail productivity coverage is opportunistic and should not present Elevated Rails as required or recommended; Quality is hidden so quality module recipes are visible before module productivity is generated without presenting Quality as a required or recommended dependency. Third-party compatibility remains opportunistic and avoids compatibility-mod dependencies.
- Weapon shooting speed overlap handling only removes rocket and cannon-shell speed effects from MIR's generated weapon shooting speed continuation. Finite vanilla weapon shooting speed technologies keep their original rocket and cannon-shell bonuses so tank cannon fire rate is not reduced.
- `mir-debug-generation-report` can be enabled to capture why each stream or base extension generated or skipped.
- The generation report also emits parser-friendly `audit schema=1` rows for stream decisions, native modifier overlaps, recipe-owner skips, compatibility planner observations, and recipe-cap warnings.
- `mir-debug-recipe-matches` can be enabled to capture matched recipe names per stream and duplicate recipe matches across streams.

## Future Overlap Policy

Future MIR features should treat overlapping native modifiers as compatibility-sensitive. If another mod already adds an infinite technology that modifies the same force statistic, MIR should prefer one of these behaviors:

- Prefer the existing owner by default.
- Warn only when the user intentionally chooses diagnostic behavior.
- Prefer MIR only when the user explicitly chooses that policy.
- Allow duplicates only when the user explicitly chooses that policy.

This is especially relevant for cargo landing pad count, cargo bay unloading distance, and any future native modifier or scripted-effect technology that other mods may also provide.

The broad skip/warn/prefer/allow native-modifier policy is deferred from `v2.1.0`. The shipped compatibility work is narrower: exact recipe-productivity owner filtering, configured vanilla productivity-family adoption, and known fully covered recipe-productivity competitor replacement.

## Compatibility Audit Pipeline

The broad mod-portal audit is local/manual because it can require Factorio credentials, large third-party downloads, and a local Factorio binary. The committed surfaces are:

- `scripts/Invoke-MIRCompatAudit.ps1`: mod-portal catalog, dependency, lockfile, optional download, and optional load-test runner.
- `scripts/MIRCompatAudit/`: portal, dependency, diagnostics-parser, and Factorio runner helper libraries.
- `scripts/Invoke-MIRExtendedTests.ps1`: tiered wrapper for static, runtime, smoke, top-25, manual-scenario, full-audit, and save-compat runs.
- `scripts/Convert-MIRCompatAuditResults.ps1`: groups load/audit results into failure classes, writes profile-candidate evidence, and writes diagnostics-only compatibility observations.
- `scripts/New-MIRCompatProfileStub.ps1`: creates review-required Lua stubs from grouped audit failures.
- `fixtures/compat-matrix/manual-scenarios.json`: curated high-risk scenarios that should not be inferred from downloads alone.
- `fixtures/compat-matrix/local-library-scenarios.json`: curated Factorio `2.1` scenarios intended for large local zip libraries such as `C:\Projects\Factorio\testmods_2.1`.
- `fixtures/compat-matrix/local-library-scenarios-2.0.json`: curated Factorio `2.0` scenarios for legacy-line local libraries such as `C:\Projects\Factorio\testmods_2.0`.
- `fixtures/compat-matrix/expected-failures.json`: reviewed expected-failure rules used by grouped reports so known external breakage can be separated from unexpected MIR regressions.
- `fixtures/compat-matrix/known-exclusions.json`: stable exclusions for official DLC, localization, and internal-only portal entries.

Local modpack zips can be supplied with `-LocalModZipDirs` or `-LocalModZips`. Local dependency libraries can be supplied separately with `-LocalModLibraryDirs` or `-LocalModLibraryZips`. The audit runner reads each zip's `info.json`, creates local lock entries with `source_path`, copies local archives into isolated Factorio runs directly from disk, and resolves missing third-party dependencies from the local library before falling back to the normal Mod Portal path. Pass `-Offline` to make missing local metadata or archives fail as dependency-resolution evidence instead of calling the Mod Portal.

The `LocalModZips` extended tier automatically enables `-IncludeRecommendedDependencies` because Factorio modpack wrapper mods often use `+` dependencies to describe the pack contents rather than strict required dependencies. `LocalModZips` treats root zip dirs as the set of individual scenarios to test. `LocalModLibraryDirs` is dependency-library-only; it does not turn every library zip into a root scenario unless the same directory is also passed through `-LocalModZipDirs`.

Use `-FactorioLine 2.1` or `-FactorioLine 2.0` to keep one audit toolchain pointed at the correct Factorio line. The line selects Mod Portal release matching, output metadata, generated local scenario names, and the default curated local scenario file. A `2.0` run still requires a Factorio `2.0.x` binary and a source tree whose metadata targets Factorio `2.0`; do not validate a legacy package with a Steam-updated `2.1.x` binary.

Catalog and lockfile only:

```powershell
.\scripts\Invoke-MIRCompatAudit.ps1 `
  -MinDownloads 10000 `
  -FactorioLine 2.1 `
  -FactorioVersions @("2.0", "2.1") `
  -MaxCandidates 100
```

Download and load-test mode requires credentials and a local binary:

```powershell
.\scripts\Invoke-MIRCompatAudit.ps1 `
  -FactorioBin "C:\path\to\factorio.exe" `
  -FactorioLine 2.1 `
  -ModPortalUsername $env:FACTORIO_USERNAME `
  -ModPortalToken $env:FACTORIO_TOKEN `
  -ScenarioTimeoutSeconds 900 `
  -DownloadMods `
  -RunLoadTests
```

Manual scenarios can now be executed with `-RunManualScenarios`:

```powershell
.\scripts\Invoke-MIRCompatAudit.ps1 `
  -FactorioBin $env:FACTORIO_BIN `
  -FactorioLine 2.1 `
  -ModPortalUsername $env:FACTORIO_USERNAME `
  -ModPortalToken $env:FACTORIO_TOKEN `
  -MaxCandidates 0 `
  -CatalogPages 0 `
  -RunManualScenarios `
  -ScenarioTimeoutSeconds 900 `
  -DownloadMods `
  -RunLoadTests `
  -OutputDir .\artifacts\compat-audit-manual
```

Sharded or resumed audits can use `-FromLockfile`, `-StartIndex`, `-Count`, and `-CandidateNames`:

```powershell
.\scripts\Invoke-MIRCompatAudit.ps1 `
  -FromLockfile .\artifacts\compat-audit-2.1-spaceage-all-10k\compat-candidates.lock.json `
  -FactorioLine 2.1 `
  -StartIndex 25 `
  -Count 25 `
  -FactorioBin $env:FACTORIO_BIN `
  -ModPortalUsername $env:FACTORIO_USERNAME `
  -ModPortalToken $env:FACTORIO_TOKEN `
  -ScenarioTimeoutSeconds 900 `
  -DownloadMods `
  -RunLoadTests `
  -OutputDir .\artifacts\compat-audit-2.1-spaceage-all-10k-shard-25
```

Grouped summaries and profile-candidate evidence are generated with:

```powershell
.\scripts\Convert-MIRCompatAuditResults.ps1 -AuditDir .\artifacts\compat-audit-manual
```

Review-only profile stubs can be generated from grouped failures:

```powershell
.\scripts\New-MIRCompatProfileStub.ps1 `
  -GroupedFailures .\artifacts\compat-audit-manual\compat-failures.grouped.json `
  -GroupId FG0001
```

Use `mir.ps1` as the preferred human entry point for repeatable local and self-hosted runs:

```powershell
.\scripts\mir.ps1 release gate
.\scripts\mir.ps1 overnight local
.\scripts\mir.ps1 audit local
.\scripts\mir.ps1 audit top25 --space-age
.\scripts\mir.ps1 report latest
.\scripts\mir.ps1 report missing-deps --run <path>
.\scripts\mir.ps1 package build
.\scripts\mir.ps1 run -Profile local-audit-2.1
.\scripts\mir.ps1 run -Profile local-audit-2.0
```

`--factorio-line <2.0|2.1>` can override a profile when you need the same command shape on a different Factorio line. For local overnight work, `overnight-local-2.1` uses the 2.1 library/scenario defaults and `overnight-local-2.0` uses the 2.0 defaults.

Use the underlying scripts directly only when debugging or composing a narrower custom run:

```powershell
.\scripts\Invoke-MIRReleaseTargetedGate.ps1
.\scripts\Invoke-MIRExtendedTests.ps1 -Tier Static,Runtime,AuditSmoke -FailFast -FailOnAuditFailures
.\scripts\Invoke-MIRExtendedTests.ps1 -Tier Top25Base,Top25SpaceAge,ManualScenarios -CollectAll
.\scripts\Invoke-MIRExtendedTests.ps1 -Tier LocalModZips -LocalModZipDirs .\tmp -CollectAll
.\scripts\Start-MIROvernightLocalSweep.ps1
.\scripts\Invoke-MIRExtendedTests.ps1 -Tier Full10KSpaceAge -IncludeFullAudit -StartIndex 0 -ShardSize 25 -CollectAll
.\scripts\Invoke-MIRExtendedTests.ps1 -Tier Full10KSpaceAge -IncludeFullAudit -FromLockfile .\artifacts\compat-audit-locks\compat-candidates.lock.json -StartIndex 25 -ShardSize 25 -CollectAll
```

`Invoke-MIRReleaseTargetedGate.ps1` is the narrow release command. It resolves the Factorio binary, picks a local mod library for the current Factorio line unless one is passed, optionally pulls the current branch, and then runs:

- the strict `Static,Runtime,AuditSmoke` gate;
- configured local smoke mods;
- one configured representative local scenario;
- grouped failure conversion;
- package rebuild, `git diff --check`, and a clean-git-status check.

The default smoke mods and representative scenario are ordinary parameters, so future release lines can reuse the same command without changing script code. It writes `release-targeted-summary.md/json` under `artifacts/release-targeted-*`.

`mir.ps1` is the stable front door for humans. It delegates to the existing scripts rather than replacing them, supports JSON run profiles from `fixtures/run-profiles/`, and exposes common commands such as `release gate`, `overnight local`, `audit local`, `audit top25 --space-age`, `package build`, `report latest`, `report missing-deps`, `report observations`, `profile stub`, and `local-index build`. Use `--factorio`, `--mods`, `--output`, `--timeout`, and `--profile` for common overrides instead of editing scripts.

`Start-MIROvernightLocalSweep.ps1` is the preferred bedtime command for the local `2.1` library. It removes one-line paste hazards, starts a transcript log, writes `run-manifest.json`, `events.jsonl`, `artifact-index.json`, and `index.html`, runs the strict release gate, then runs the local sweep with `-CollectAll`. The underlying prioritized local sweep covers curated combinations from `fixtures/compat-matrix/local-library-scenarios.json`, generated all-local/cluster stress scenarios, and then each individual local root zip. Missing dependencies and impossible mod combinations are expected to appear as grouped failures; they are still useful evidence because they distinguish "not testable with this local library" from actual MIR generation regressions. `compat-observations.md/json/csv` records diagnostics-only planner rows and cap warnings. `Show-MIROvernightSummary.ps1` summarizes the next-morning triage views across the whole output tree.

Use `Test-MIRLocalModLibraryCatalog.ps1` before a local sweep when you need a
metadata-only gate. It reads local zip `info.json` files, catalogs available mod
names, and fails if committed local-library scenario roots are missing from the
library.

`GeneratedLocalScenarios` creates scenarios from local zip metadata: one all-local mega scenario, cluster scenarios for planet/Space Age content, BZ/resource chains, Bob, Krastorio/K2SO, production/fluid/casting/resource-flow mods, and logistics/transport mods. Add `-IncludeGeneratedLocalPairwise -GeneratedLocalPairwiseLimit 40` to the wrapper when you want a capped pairwise pass inside high-risk local clusters. `LocalModZips` can be sharded with `-ShardLocalModZips -StartIndex N -ShardSize M`; without `-ShardLocalModZips`, it tests every local root.

For idea-mod and overhaul campaigns, do not treat a full-folder load as the main proof. Run `MIR + one mod`, `MIR + one family`, `MIR + known conflict pair`, `MIR + representative overhaul stack`, and only then a full chaos-folder smoke as non-blocking evidence. Public compatibility claims require exact mod versions, role enums, validation artifacts, save-compatibility notes, and clear non-ownership notes for behavior MIR deliberately leaves external.

Do not mix Factorio lines unintentionally. The current `2.x` package line targets Factorio `2.1`; with a Factorio `2.1.x` binary, use `testmods_2.1` as the primary local library. `testmods_2.0` is useful for inventory and future legacy tests, but true `2.0` runtime validation requires a compatible Factorio `2.0` binary and a mod package line that can load there.

Use `-CollectAll` for exploratory or overnight runs. It prevents the wrapper from forwarding scenario-level `-FailFast` into audit tiers, so all selected scenarios can produce artifacts. Use `-FailFast -FailOnAuditFailures` for strict gates; after conversion, the wrapper reads `compat-failures.grouped.json` and fails the tier when unexpected grouped failures remain.

`AuditSmoke` is intentionally deterministic. On Factorio `2.1` it runs the committed `space-age-baseline` manual-scenario metadata path; on Factorio `2.0` it runs the base-only `base-baseline` scenario. It is not a broad compatibility claim; use `Top25Base`, `Top25SpaceAge`, and `ManualScenarios` for exploratory external-mod coverage.

Generated lockfiles and reports belong under ignored output directories such as `artifacts/compat-audit/` or `build/compat-audit-*`. Do not commit downloaded mod zips or one-off portal reports. Commit only scenario fixtures, known exclusions, code changes, and small compatibility profiles that are justified by repeatable audit evidence.

Load-test mode enables the root candidate, its required Mod Portal dependency closure, and required official built-in mods such as Space Age, Quality, Elevated Rails, or Recycler without trying to download official built-ins from the portal. `-IncludeSpaceAge` requires `space-age` and then enables only the official companion mods that actually exist beside the selected Factorio binary. Downloaded archives are checked against their Mod Portal SHA1 before reuse, and load-test results include parsed MIR audit rows when generation diagnostics are forced on in the copied test mod.

The isolated load runner writes explicit entries for the official built-ins. Installed official mods that are not requested by the scenario are disabled instead of being inherited from the user's normal Factorio install. When a scenario requires `space-age`, the runner requires `space-age` and enables whichever official companion mods are present beside the selected Factorio binary, so Factorio `2.0` and `2.1` runs do not share a hardcoded bundle assumption.

Scenarios with unresolved required dependencies are skipped before Factorio startup by default and grouped as dependency failures. Pass `-ContinueOnDependencyFailure` only when intentionally testing a partial modset. Each Factorio load check has a timeout controlled by `-ScenarioTimeoutSeconds`; timed-out processes are killed and grouped as `timeout` failures rather than blocking the entire run.

Load-test runs print per-scenario start/result progress lines with the scenario index, type, root mods, dependency-failure count, pass/skip/timeout status, exit code, parsed audit-row count, and elapsed seconds. `load-results.json` is checkpointed after each scenario, so a partially interrupted run can still be inspected and converted. Extended and overnight wrapper runs also write self-describing manifests, JSONL events, artifact indexes, and static HTML reports. For unattended local runs, pipe all streams through `Tee-Object` so progress stays visible in the terminal and is also written to an overnight log.

The audit-log parser ignores blank Factorio log lines before parsing MIR's structured audit rows. This keeps overnight sweeps resumable and convertible even when a third-party mod or Factorio itself emits empty log lines.

The grouped converter writes `missing-dependencies.md`, `missing-dependencies.json`, and `missing-dependencies.csv` next to `compat-summary.md`. Use those files as the local-library completion list before treating dependency failures as MIR compatibility problems.

Do not immediately patch code from the first local-library failure. First classify the evidence: missing local zip, known modset incompatibility, benign external owner suppression, repeated split-family pattern, MIR-generated prototype crash, or timeout. Download missing dependencies and rerun affected scenarios before promoting a failure to MIR compatibility work.

Expected failures should be added only after review to `fixtures/compat-matrix/expected-failures.json`. The converter still reports them, but separates `expected_count` from `unexpected_count`; strict wrapper gates fail on unexpected groups.

Some audit observations are expected by policy even without a scenario-specific expected-failure rule. In particular, a successful load test where MIR skips a stream because a required prototype is absent is a normal compatibility gate, and a successful load test where MIR suppresses recipe productivity under an unknown external infinite owner is conservative behavior rather than a release-blocking failure. Those rows stay visible in `compat-failures.grouped.json` and can still produce review-only profile candidates, but they do not increment `unexpected_count`.

The GitHub workflow `.github/workflows/extended-compat-audit.yml` runs the same wrapper on self-hosted runners. It is intentionally not a normal hosted CI job because it needs a local Factorio binary, credentials, and enough disk for third-party archives and run artifacts.

## Compatibility Planning Target

The current implementation has the right compatibility seams, but the long-term system should make a complete plan object the central artifact before any prototype mutation happens:

```text
discover facts
  -> classify owners
  -> build complete plan
  -> validate plan
  -> mutate prototypes
  -> emit audit rows from the plan
```

The planning object should include stream-level and recipe-level decisions such as generate, adopt, replace, suppress, and conflict. Diagnostics and audit reports should be emitted from that same plan so the report describes the exact decisions that were applied. This keeps future compatibility support testable before mutation, allows plan comparisons across modsets, and keeps profile additions declarative.

Profile changes should remain conservative:

- Unknown external infinite recipe-productivity owners suppress MIR by default.
- Known competitor replacement requires an explicit profile, anchored technology matching by default, full recipe coverage, matching productivity `change` values, lab-compatible replacement science, and no other blocking external owner.
- Vanilla-family adoption requires an explicit configured family and safe owner behavior.
- Finite progression chains from other mods are not removed unless a future profile explicitly models that chain and validates the migration/safety story.

Release policy for compatibility-heavy changes:

```text
static validation passed
runtime Factorio validation passed
compat audit smoke passed
package build passed
git diff --check passed
```

Do not publish a compatibility-heavy archive from static validation alone. After generator, owner-classification, profile, adoption, or replacement refactors, run runtime validation with `FACTORIO_BIN` configured before release.

## Legacy Backport Model

The Factorio `2.0` legacy release More Infinite Research `v1.9.0` was released from the `legacy` branch, backported from the tested More Infinite Research `v2.0.5` Factorio `2.1` quick-patch codebase. `v1.9.1` follows the same snapshot-port model from the tested More Infinite Research `v2.1.0` source point. The next transition port is `v1.9.2` from the tested `v2.2.0` source point. The older planned `v1.9.7`, `v1.9.8`, and `v1.9.9` Factorio `2.0` ladder is superseded by the locked post-`1.9.2` target-line policy unless the maintainer explicitly revives it.

The expanded older-line ladder for Factorio `1.1` through `0.6` lives in `docs/archive/2.x/legacy-backport-cadence.md`. Those ports should be treated as separate target-line compatibility, archive, or museum releases, not as automatic feature-parity claims.

The daily celebration cadence does not change the compatibility model: each
archive still needs target-line metadata, unsupported-surface guards, package
evidence, and target-line validation or an explicit release-note caveat.

Legacy should not be reconstructed commit-by-commit from older release history. `v1.9.0` ported the tested `v2.0.5` snapshot: current MIR generator, diagnostics, recipe matching, science-pack handling, compatibility cleanup, docs structure, locale, and validation infrastructure with Factorio `2.1`-only surface area removed or guarded.

Legacy `info.json` must use Factorio `2.0` metadata:

```json
{
  "version": "1.9.1",
  "factorio_version": "2.0",
  "dependencies": [
    "base >= 2.0",
    "(?) quality",
    "? space-age"
  ]
}
```

Do not carry the Factorio `2.1.x` base or optional official DLC dependency floors into legacy unless a later Factorio `2.0` validation run proves a specific ordering requirement.

Known legacy `1.9.x` exclusions:

- `research_cargo_bay_unloading_distance`
- `research_cargo_landing_pad_count`
- `max-cargo-bay-unloading-distance`
- `cargo-landing-pad-count`
- any scripted agriculture path that depends on unavailable agricultural tower events or entity fields, if a future default-on claim depends on it
- any pump, pipeline, or Space Age logistics prototype field added after the Factorio `2.0` target; no pump or pipeline feature ships in `1.9.0`

Keep these architecture pieces from the tested current-line source snapshot unless Factorio `2.0` validation proves a specific incompatibility: `data-final-fixes.lua` generation, lab-input science-pack discovery, lab incompatibility policy, science-pack ingredient policy, recipe matching, diagnostics, base-tech extension safety, opportunistic compatibility cleanup, validation/package parity tooling, docs structure, and locale structure.

Validation is branch-aware from `info.json`: Factorio `2.1` checks require cargo streams and the `2.1.8` dependency floor, while Factorio `2.0` checks reject Factorio `2.1` dependency floors, require those cargo modifier strings to be absent from direct-effect stream definitions, skip Factorio `2.1` cargo runtime fixtures, and expect the package to build from the active `1.9.x` metadata.

## Opportunistic Integrations

These integrations do not add mod-page dependencies. More Infinite Research handles them when their prototypes are already visible, and skips safely when they are absent:

- Advanced Solar HR (`Advanced-Electric-Revamped-v16`): advanced, elite, and ultimate solar panel/accumulator recipes are covered by the electric energy productivity tiers.
- Better Robots Extended (`Better_Robots_Extended`): competing infinite worker robot storage research is removed when `mir-prefer-this-mod-for-competing-techs` is enabled and MIR's `worker-robots-storage` base extension is enabled.
- OCs Ammo and Armor (`OCs_ammo_casting`): foundry, biochamber, and electromagnetic plant recipes that output covered ammunition, explosive, or armor component items are picked up by the existing output-based streams.
- OCs Stone Casting (`OCs_stone_casting`): foundry recipes that output covered landfill, brick, wall, concrete, refined concrete, foundation, rail, gate, or furnace items are picked up by the existing output-based streams. Stone-only output remains outside the split Space Age landfill/artificial-soil/molten-metal policy unless a dedicated stream is added later.
- Fluid Quality Imprinting (`fluid-quality-imprinting`): quality-imprinting recipes that output covered plate and intermediate items are picked up by the existing output-based streams.
- Plates n Circuit Productivity (`plates-n-circuit-productivity`): competing plate and circuit productivity technologies are replaced when `mir-prefer-this-mod-for-competing-techs` is enabled and all recipe effects on the competing technology are covered by enabled MIR streams.
- Bioflux Productivity (`bioflux-productivity`) and Fish Productivity (`fish-productivity`): matching infinite recipe-productivity technologies can be replaced when MIR covers the same recipe with the same productivity value.
- Science Packs Productivity (`Science_packs_productivity`): infinite level-4 official science-pack productivity technologies can be replaced when the active MIR science-pack stream covers the same recipe and effect value.
- Productivity Research (`ProductivityResearch`) and Productivity Research for Everyone variants (`ProductivityResearchForEveryone`, `ProductivityResearchForEveryoneFG`): generated infinite recipe-productivity technologies can be replaced on exact coverage and value match.
- Expanded Productivity Research (`ExpandedProductivityResearch`) and Crafting Efficiency (`crafting-efficiency-2`): generated infinite recipe-productivity technologies can be replaced only when MIR's enabled streams prove exact recipe and value coverage.
- Research Productivity (`Research_Productivity`): MIR's base-game lab productivity stream is skipped when an infinite `laboratory-productivity-4` has the native `laboratory-productivity` effect.
- Panglia-style planet mods: additional productivity-allowed rocket fuel and low density structure recipes can be adopted into the existing vanilla Space Age `rocket-fuel-productivity` and `low-density-structure-productivity` technologies when those vanilla owners are safe.
- AAI Loaders style loader mods: AAI-style and tier-named loader outputs are picked up by transport belt productivity when their recipes are visible. `2.2.0` diagnostics also classify entity-backed loader manufacturing from item `place_result`, placed loader entity type, and recipe-output evidence.
- Big Mining Drill and Omega Drill style drill mods: `big-mining-drill`, `omega-drill`, `omega-tau`, and broader modded `*-mining-drill` / `*-drill` outputs are picked up by mining drill productivity when their recipes are visible. `2.2.0` diagnostics keep drill manufacturing productivity separate from native mining-yield modifiers.
- Custom science packs from mods such as Castra, PlanetLib-based planets, or ATAN Nuclear Science are picked up opportunistically when they are active lab inputs and have visible recipes that output the pack item.

Large mod packs and utility mods such as Alien Biomes, Informatron, Jetpack, AAI, and Helmod usually do not need explicit recipe productivity support unless they add recipes for items, fluids, or science packs covered by one of this mod's streams. When they do, output-based matching should pick up visible recipes automatically.

### Support Lanes For Older Mods

MIR can add and test support for mods that currently advertise an older Factorio line. Upstream Factorio-version metadata is not a reason to avoid implementing safe output-based or fixture-backed support, because the same support may be useful when the external mod updates and when MIR backports behavior to a Factorio `2.0` branch.

Machine-readable support data lives in `fixtures/compat-matrix/support-lanes.json`
and `fixtures/compat-matrix/claims.json`. Static validation lints those files so
current fixture-backed claims list fixtures, generated streams have manifest
rows, and public text stays narrower than "full support" unless a separate
external load profile proves that claim.

Claims must stay precise:

- A representative fixture proves MIR's behavior for the recipe family or science-pack shape.
- A real external load profile proves that a named mod/version loads with a named MIR package and Factorio binary.
- Public copy should say "loader recipes are covered by belt productivity when visible" rather than "full AAI Loaders support" unless the broader external load profile has passed.
- Backport candidates should keep the same behavioral boundary and rerun the legacy validation lane instead of weakening current-line support.

## Known Limits

- No mod can observe another mod's later `data-final-fixes.lua` mutations unless a user, modpack, or future targeted integration imposes a later load order.
- Lab validation prevents impossible research ingredients, but it cannot infer every overhaul mod's intended progression.
- Recipe productivity technologies remain bounded by Factorio's recipe productivity cap even when research levels are infinite.
- Vanilla Space Age productivity technologies remain authoritative for processing units, low density structures, plastic, and rocket fuel. Where those configured families have additional productivity-allowed recipes that are not exactly owned by another infinite technology, MIR adopts them into the existing vanilla infinite productivity technology instead of generating a parallel MIR technology.
- The existing-save refresh for configured vanilla productivity-family adoption is keyed by the actual adopted `owner|recipe|change` signature, not only by a fixed feature version. Adding or removing a planet mod that changes the adopted recipe set can therefore trigger one technology-effect reset for the affected save.
- Module productivity can include Quality modules because the current Factorio `2.1` line uses a hidden optional Quality dependency for load order. The dependency is hidden to avoid presenting Quality as a required or recommended mod-page dependency.
- Existing prototype IDs are kept stable unless a tested migration is provided. `v2.0.5` provides a JSON migration for the intentional trash-slot-to-inventory technology consolidation and adds control-stage storage under the More Infinite Research namespace.
- Runtime scripted features avoid per-tick scanning by default. If a future feature needs active scanning, it should be disabled by default, clearly labeled experimental, or split into a companion mod.
- Scripted technologies must document storage keys, recomputation triggers, reversal behavior, disabling behavior, and multi-force behavior before implementation.

## Required Manual Test Matrix

Run each case from a clean Factorio user data directory or with a controlled mod set:

1. Base game only.
2. Elevated Rails only.
3. Recycler only.
4. Quality enabled with its dependencies.
5. Base-only with default `research_cargo_landing_pad_count`, verifying the generated technology is skipped because Space Age is absent.
6. Space Age 2.1.8+ enabled, verifying cargo bay unloading distance and cargo landing pad count research appear after their required unlocks.
7. Space Age 2.1.8+ with `research_cargo_landing_pad_count` disabled, verifying the checkbox skips the generated technology cleanly.
8. Space Age 2.1.8+ with a Maraxis-like duplicate cargo fixture, verifying overlapping cargo modifiers are reported diagnostically while MIR's cargo technologies still load.
9. Base-only and Space Age fluid-productivity fixture runs, verifying oil, lubricant, sulfuric acid, acid neutralization, and thruster propellant recipe ownership.
10. Startup pipeline extent fixture runs with non-default dropdown multipliers, verifying common fluid boxes are mutated only when enabled.
11. Space Age with Panglia or a Panglia-like fixture, verifying extra rocket fuel and low density structure recipes adopt into vanilla productivity technologies.
12. Plates n Circuit Productivity or the local fixture enabled, verifying fully covered competing technologies are removed only after MIR replacement effects exist.
13. Better Robots Extended enabled.
14. A fixture mod that adds a science pack as an ordinary `item` and adds it to a lab.
15. A fixture mod that adds a custom lab with a different science-pack input set.
16. A fixture mod that adds recipes in `data-final-fixes.lua`.
17. Existing save upgraded from the latest 1.x release.

Post-v2.0 scripted feature releases also require these named saves/scenarios:

1. Fresh Space Age save with no other mods.
2. Existing v2.0.0 More Infinite Research save upgraded to the candidate release.
3. Save with spoilable items already on belts, in chests, in labs, in rockets, and on platforms.
4. Save with multiple player forces.
5. Large Gleba farm with thousands of tower-owned plants.
6. Save with a scripted feature enabled, researched, then disabled.
7. Save with Maraxis-like duplicate cargo landing pad technology.
8. Save with custom science packs and custom labs.
9. Save without Space Age.
10. Factorio 2.0 legacy-branch subset save.

For each case, verify:

- Factorio reaches the main menu without prototype errors.
- Generated technologies have non-empty science-pack ingredients.
- At least one lab accepts each generated technology's full science-pack set.
- Default base-only runs do not load direct DLC asset paths. The
  `mir-use-installed-space-age-icons` startup setting is an explicit opt-in for
  players who have official DLC icon files installed but disabled and want MIR
  to reference those local icon files.
- Logs show skipped or reduced streams clearly and do not show stack traces.
- Finite vanilla weapon shooting speed effects are preserved even when the overlap adjustment setting is enabled. The setting only affects MIR's generated continuation.

For named manual save scenarios and release-specific manual tests, see `docs/maintainer/manual-test-plan.md`.

## Local Validation Harness

The repository includes local fixture mods under `fixtures/` and a runner at `scripts/Invoke-MIRValidation.ps1`.

Static checks only:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

Runtime load check:

```powershell
$env:FACTORIO_BIN = "C:\path\to\factorio.exe"
.\scripts\Invoke-MIRValidation.ps1
```

Set `$env:FACTORIO_LOG` or pass `-FactorioLog` when the Factorio log is not at the default Windows user-data path.

The runtime check copies this repo and the fixture mods into isolated temporary user-data mod directories, adds test-only dependencies from the copied mod to the fixture mods for deterministic load order, writes fixture `mod-list.json` files, and asks Factorio to create saves. It is intentionally a load/prototype validation harness, not a gameplay test.

The runtime fixture run enables the generation diagnostics report in the copied mod and covers both lab incompatibility policies. The default `reduce` scenario asserts that science-pack productivity generated with the custom item-based fixture science pack included. The `skip` scenario forces the copied setting default to `skip` and asserts that the intentionally incompatible science-pack productivity stream is skipped instead of reduced. Additional runtime scenarios force the science-pack ingredient policies, require the end-game prerequisite gate, verify checkbox-enabled and checkbox-disabled stream/base-extension behavior, keep cargo landing pad count default-on while proving it skips without Space Age, assert Space Age cargo logistics effect shape with default cargo settings, add a fixture finite vanilla-chain level before MIR to prove existing levels are preserved while MIR extends after them, assert broad generation integrity in both base-only and Space Age runs, enable the normally disabled inserter-capacity continuation in both base-only and Space Age runs, assert weapon shooting speed overlap handling preserves finite vanilla tank cannon speed, assert AAI-style loader recipes receive belt productivity, assert standalone big-mining-drill recipes receive mining drill productivity, assert ATAN-style Nuclear Science packs receive science-pack productivity with lab-compatible science, and assert Omega-style drill recipes receive mining drill productivity. The diagnostics report also emits compiler rows for typed fact summaries, generated-technology decisions, lab matrices, loop-risk flags, rule surfaces, and useful cap estimates. The expected Factorio log file is part of the validation evidence; if it is missing, runtime validation fails.

Static validation builds an ignored validation archive from the current source tree based on `info.json`. The package must use the matching `<name>_<version>/` root, contain matching `info.json` metadata, include locale, top-level data-stage and control-stage files, core prototype modules, migrations, README, changelog, license, and thumbnail, match the repository contents for packaged source and locale files, and avoid developer docs, build output, fixtures, scripts, Git, and temporary/editor artifacts. The committed `dist/` archive is the upload artifact, not the live source-parity fixture for every documentation-only commit.

## Fixture Designs

### Item Science Pack Fixture

Create a local test mod that:

- Adds `mir-fixture-science-pack` as an `item`.
- Adds a recipe that produces `mir-fixture-science-pack`.
- Adds `mir-fixture-science-pack` to the vanilla lab input list.
- Unlocks that recipe from a technology.

Expected result: `mir-fixture-science-pack` can be discovered as a science pack, ordered after known vanilla packs, mapped to its unlock prerequisite when used, and included in science-pack productivity.

### Custom Lab Fixture

Create a local test mod that:

- Copies the vanilla lab prototype to `mir-custom-lab`.
- Sets `mir-custom-lab.inputs` to a deliberately smaller or different pack set.
- Optionally adds a second custom science pack that only this lab accepts.

Expected result: generated technologies are not allowed to combine science packs that no single lab accepts.

### Late Recipe Fixture

Create a local test mod that:

- Adds or mutates recipes in its own `data-final-fixes.lua`.
- Declares dependency ordering so More Infinite Research loads after it when testing positive capture.

Expected result: recipe streams can discover late recipes when load order makes those recipes visible, and the documented load-order limitation is visible when order is reversed.

### Science-Pack Productivity Assertion Fixture

Create a local test mod that:

- Depends on More Infinite Research and the item science-pack fixture.
- Runs after MIR in `data-final-fixes.lua`.
- Reads `recipe-prod-research_science_pack_productivity-1`.
- Fails loading if the fixture science-pack recipe is not present as a `change-recipe-productivity` effect.

Expected result: custom item-based science packs that are active lab inputs and have visible recipes receive science-pack productivity effects.

### ATAN Nuclear Science Fixture

Create a local test mod pair that:

- Adds a visible `nuclear-science-pack` item and recipe.
- Adds `nuclear-science-pack` to active lab inputs.
- Unlocks the science pack from an ATAN-style nuclear science technology.
- Adds a non-science `atan-atom-forge` recipe as an adjacent surface.
- Runs a post-MIR assertion in `data-final-fixes.lua`.
- Reads `recipe-prod-research_science_pack_productivity-1`.
- Fails loading if the science pack recipe is missing from the science-pack productivity effects.
- Fails loading if the atom forge recipe is included in the science-pack productivity effects.
- Fails loading if the generated technology does not include the nuclear science pack in its lab-compatible science set.

Expected result: visible custom science-pack recipes receive science-pack productivity and unlock-derived prerequisites, while adjacent non-science buildings remain outside the science-pack stream.

### Generation Integrity Assertion Fixture

Create a local test mod that:

- Runs after More Infinite Research in both base-only and Space Age scenarios.
- Reads every generated `recipe-prod-*` stream technology and fails loading unless each one is an infinite upgrade with effects and a count formula.
- Reads every enabled vanilla numbered extension chain and fails loading unless there is exactly one infinite serial continuation after the highest finite level.
- Confirms disabled vanilla extension chains, such as the default-off `inserter-capacity-bonus`, do not generate until the validation harness force-enables them.
- Reads every infinite `change-recipe-productivity` effect and fails loading if any recipe has more than one infinite productivity owner.
- Confirms base-only `processing-unit`, `low-density-structure`, `plastic-bar`, and `rocket-fuel` productivity are owned by the corresponding MIR generated chain.
- Confirms Space Age `processing-unit-productivity`, `low-density-structure-productivity`, `plastic-bar-productivity`, and `rocket-fuel-productivity` remain the only owners for their covered vanilla recipes.
- Confirms circuit recipes stay split by recipe ID: `electronic-circuit` and `advanced-circuit` are MIR-owned, while `processing-unit` is MIR-owned only without Space Age and vanilla-owned with Space Age.

Expected result: MIR creates one serial chain per intended generated technology, creates zero chains for disabled defaults, extends vanilla numbered chains only once, and never creates a parallel infinite productivity owner for a recipe already owned by vanilla Space Age.

### Lab Skip Policy Assertion Fixture

Create a local test mod that:

- Depends on More Infinite Research, the custom lab fixture, and the item science-pack fixture.
- Runs after MIR in `data-final-fixes.lua`.
- Expects `mir-lab-incompatibility-policy = skip`.
- Fails loading if `recipe-prod-research_science_pack_productivity-1` still exists after MIR sees the deliberately incompatible full lab-input set.

Expected result: when the skip policy is active, MIR skips the incompatible science-pack productivity stream instead of reducing it.

### Omega Drill Productivity Fixture

Create a local test mod pair that:

- Adds visible `omega-drill` and `omega-tau` item recipes.
- Runs a post-MIR assertion in `data-final-fixes.lua`.
- Reads `recipe-prod-research_mining_drill-1`.
- Fails loading if either Omega-style recipe is missing from the mining drill productivity effects.

Expected result: Omega Drill style recipes and broader visible modded `*-drill` / `*-mining-drill` outputs are covered by mining drill productivity.

### Big Mining Drill Productivity Fixture

Create a local test mod pair that:

- Adds a visible `big-mining-drill` item recipe.
- Runs a post-MIR assertion in `data-final-fixes.lua`.
- Reads `recipe-prod-research_mining_drill-1`.
- Fails loading if the `big-mining-drill` recipe is missing from the mining drill productivity effects.
- Fails loading if the matched effect uses anything other than the high-tier `+0.05` drill bucket.

Expected result: standalone Big Mining Drill style recipes are covered by the existing mining drill productivity stream without creating a separate research line.

### AAI Loader Belt Productivity Fixture

Create a local test mod pair that:

- Adds visible AAI-style loader recipes for basic, fast, express, and turbo loader tiers.
- Runs a post-MIR assertion in `data-final-fixes.lua`.
- Reads `recipe-prod-research_belts-1`.
- Fails loading if any loader recipe is missing from the belt productivity effects.
- Fails loading if a loader recipe is assigned to the wrong logistics tier value.

Expected result: loader crafting recipes are covered by transport belt productivity by tier, while loader entity behavior, operating modes, fluids, and compatibility hooks remain outside MIR ownership.

### Fluid Productivity Fixture

Create a local test mod that:

- Runs after More Infinite Research in base-only and Space Age scenarios.
- Reads each generated fluid-output productivity technology.
- Fails loading if oil processing, oil cracking, lubricant, sulfuric acid, acid neutralization, thruster fuel, or thruster oxidizer recipes have zero or multiple infinite productivity owners.
- Fails loading if barrel-emptying recipes are covered by the lubricant or sulfuric acid streams.

Expected result: fluid-output recipe productivity is owned by exactly one MIR stream per recipe, acid neutralization is covered by sulfuric acid productivity when present, and Space Age thruster propellant streams appear only when their fluid prototypes exist.

### Pipeline Extent Fixture

Create a local test mod that:

- Runs after More Infinite Research with `mir-pipeline-extent-multiplier` set to a non-`100%` dropdown value.
- Reads representative pipe, pipe-to-ground, and storage-tank fluid boxes.
- Fails loading if their `max_pipeline_extent` values do not reflect the startup multiplier.

Expected result: the startup-only pipeline multiplier mutates common fluid boxes when explicitly enabled and is inert at the default `100%`.

### Weapon Speed Safety Fixture

Create a local test mod that:

- Runs after More Infinite Research.
- Enables the weapon-speed overlap adjustment scenario.
- Fails loading if finite vanilla `weapon-shooting-speed-5` or `weapon-shooting-speed-6` loses `cannon-shell` speed effects.
- Fails loading if MIR's generated weapon shooting speed continuation keeps `rocket` or `cannon-shell` overlap effects when the dedicated replacement techs are active.

Expected result: vanilla tank cannon fire rate is preserved while MIR avoids duplicate infinite rocket/cannon-shell speed scaling in its generated continuation.

## Release Checklist

- Run `.\scripts\Build-MIRPackage.ps1` to refresh the versioned zip in `dist/`.
- Run `rg "data.raw.tool|tool_exists|has_tool|PACKS_ALL" prototypes` and confirm no old science-pack authority remains.
- Run `rg "icon_mipmaps" prototypes` and confirm generated icons do not add it.
- Run `.\scripts\Invoke-MIRValidation.ps1 -StaticOnly`.
- Confirm `changelog.txt` uses Factorio's 99-dash format and one-line bullets at or below 132 characters.
- Confirm `info.json` declares `base >= 2.1.8`, hidden optional Elevated Rails and Quality ordering, and visible optional Recycler and Space Age ordering dependencies only.
- Confirm package validation reports the expected root, matching metadata, included runtime source, locale, migrations, README, changelog, license, thumbnail, and no forbidden artifacts for the archive built from the current source tree.
- Confirm package validation reports packaged source and locale parity with the repository.
- Confirm runtime fixture validation covers both the default `reduce` lab policy and forced `skip` lab policy.
- Confirm runtime fixture validation covers `configured`, `space`, `space-and-promethium`, `space-age-progression`, `official-progression`, `mod-progression`, `all-official`, and `all` science-pack ingredient policies, the end-game prerequisite gate, and the base-only cargo landing pad count skip.
- Confirm runtime fixture validation covers checkbox-enabled and checkbox-disabled behavior for streams and base extensions.
- Confirm runtime fixture validation covers Space Age cargo logistics effect types, modifiers, costs, research times, prerequisites, and official science-pack ingredients.
- Confirm runtime fixture validation covers fluid-output productivity ownership in base-only and Space Age scenarios.
- Confirm runtime fixture validation covers startup pipeline extent scaling when the multiplier is enabled.
- Confirm runtime fixture validation covers preserving an existing finite vanilla-chain level before adding MIR's generated infinite continuation.
- Confirm runtime fixture validation covers broad generation integrity in base-only and Space Age runs, including all enabled vanilla numbered extension chains, the checkbox-enabled inserter-capacity continuation, generated `recipe-prod-*` technology shape, single-owner recipe productivity, configured vanilla productivity-family adoption/conflict cases, and Plates n Circuit Productivity replacement/partial-coverage behavior.
- Confirm runtime fixture validation covers preserving finite vanilla weapon shooting speed cannon-shell effects under MIR's overlap setting.
- Confirm runtime fixture validation covers AAI-style loader recipe productivity under the belt stream.
- Confirm runtime fixture validation covers standalone Big Mining Drill recipe productivity under the mining drill stream.
- Confirm runtime fixture validation covers ATAN-style Nuclear Science pack productivity under the science-pack stream.
- Confirm runtime fixture validation covers Omega-style drill recipe productivity.
- Load Factorio with the manual matrix above.
- Confirm `changelog.txt` has the release version and date.

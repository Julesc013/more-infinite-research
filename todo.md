# M.I.R. TODO

Updated: 2026-07-09

This is the active task list for MIR 3.0.0 and later. It should contain future
work, current gates, deferred decisions, recurring release checks, and issue
creation tasks. Completed 2.x and 1.9.x transition work is archived instead of
being kept as an ever-growing checklist.

Current assumptions:

- `2.2.0` is released as-is.
- `1.9.2` is released from `legacy` as-is.
- MIR 3.0.0 is the validated Factorio `2.1` source anchor on `main` and
  `dev`.
- MIR 2.3.0 is published from `legacy` as the Factorio `2.0` port of that
  source anchor. Treat the exact validated
  `dist/more-infinite-research_2.3.0.zip` recorded in `.mir/branches.yml` as
  immutable.
- The shipped MIR 3 structure is Factorio root wrappers, `prototypes/mir/`
  implementation, and declarative `prototypes/streams/` data tables.
- Old `prototypes/compat/`, `prototypes/lib/`, `prototypes/mir/legacy/`,
  `prototypes/planner/`, `control/`, and broad root-helper shims must stay
  absent from the shipped 3.x line.
- Keep `todo.md` as this root executable future-work ledger.
- Keep `dist/` as immutable published archive evidence. Build or refresh only
  the unpublished target archive being released.
- Do not reopen the 2.x or 1.9.x task ledgers unless a regression, security
  issue, package correction, or explicit maintainer decision requires it.

Use `docs/releases/3.0.0-plan.md` for release scope, product boundaries,
rationale, and high-level explanations. Use
`docs/archive/2.x/completed-task-ledger.md` for the historical completed task
ledger. Use `docs/archive/2.x/post-2.0-feature-plan.md` for the deeper idea
archive, `docs/archive/2.x/legacy-backport-cadence.md` for historical older-line
backport planning, and `docs/maintainer/backporting.md` for the locked
post-`2.2.0` target-line policy. Use `changelog.txt` as the authoritative
past-change ledger for shipped player-facing changes.

## Working Rules

- Target `dev` for MIR 3.0.0 Factorio `2.1` development.
- Treat MIR 3.0.0 as an architecture, contract, migration, fixture, and
  maintainability release before adding broad new gameplay generation.
- Keep generated technology names stable unless a tested migration exists.
- Prefer native modifiers and recipe productivity.
- Scripted effects must be event-driven, bounded, reversible where practical,
  and documented.
- Do not add broad `on_tick` scans for inventories, belts, containers, item
  stacks, surfaces, or all entities.
- Never add `character-item-pickup-distance` or `character-loot-pickup-distance`
  technology effects.
- Keep past shipped changes in `changelog.txt`; release notes and mod-portal
  copy are derivative summaries.
- Keep `docs/releases/3.0.0-plan.md` synchronized with this file and
  `changelog.txt`, but at a higher level with rationale and scope boundaries.
- Treat the compatibility planner as the contract between prototype discovery,
  owner classification, validation, mutation, and diagnostics.

## Archived Historical Ledgers

- Historical completed task ledger: `docs/archive/2.x/completed-task-ledger.md`
- Historical 2.2 feature intake: `docs/archive/2.x/2.2.0-feature-intake.md`
- Historical post-2.0 feature plan: `docs/archive/2.x/post-2.0-feature-plan.md`
- Historical backport cadence: `docs/archive/2.x/legacy-backport-cadence.md`

## v3.0.0 Compatibility Compiler

This is now the active development line. `2.2.0` and `1.9.2` are treated as
released as-is; do not reopen their task ledgers unless a regression, security
issue, or packaging correction forces it. Use
`docs/architecture/compatibility-compiler-charter.md` as the scope boundary.
The goal is architecture, contracts, migrations, fixtures, and maintainability,
not broad new gameplay generation.

### v3.0.0 Final Hardening

- [x] Keep Factorio root lifecycle files as thin wrappers into
  `prototypes/mir/stage/`.
- [x] Keep active shipped implementation under `prototypes/mir/`, with
  `prototypes/streams/` retained only as declarative stream data.
- [x] Keep published `dist/` archives immutable and route validation packages
  through ignored `build/` paths.
- [x] Preserve the root `todo.md` ledger as source evidence, not package
  content.
- [x] Run strict zero legacy inventory with
  `.\scripts\mir.ps1 legacy inventory --check`.
- [x] Run architecture validation with
  `.\scripts\Invoke-MIRValidation.ps1 -ArchitectureOnly`.
- [x] Run static validation after source-formatting hardening.
- [x] Run Factorio `2.1` runtime fixture validation on the release candidate.
- [x] Run the targeted release gate against ignored package output.
- [x] Compare final planner/report rows with the 3.0 regression baseline and
  document any intentional differences.
- [x] Bump `info.json` to `3.0.0` only after release gates are clean.
- [x] Add the `3.0.0` changelog section with player-facing shipped changes.
- [x] Build the final `dist/more-infinite-research_3.0.0.zip` archive only
  from the validated `3.0.0` source tree.

Final gate evidence:

- Final targeted gate artifact:
  `artifacts/release-targeted-20260708-183311`.
- Final package:
  `dist/more-infinite-research_3.0.0.zip`.
- Final package SHA-256:
  `E9A644468217D6B8B07F30E92179BE7BB2DFE951A14F211C1E924A5A505ECCDC`.
- Regression comparison:
  strict audit `814 -> 814`, repair smokes `1820 -> 1820`, representative
  scenario `924 -> 924`; observation hashes unchanged, claim hash unchanged,
  unexpected count stayed `0`.

Reference docs:

- `docs/architecture/module-boundaries.md`
- `docs/capabilities/README.md`
- `docs/compatibility/policy-overlays.md`
- `docs/reference/schemas/decision-record.md`
- `docs/reference/schemas/stream-manifest.md`
- `docs/compatibility/claim-levels.md`
- `docs/maintainer/testing.md`
- `docs/releases/3.0.0-migration-guide.md`
- `docs/maintainer/README.md`
- `docs/adr/`

### v3.0.0 Alpha 1: Skeleton And Contracts

- [ ] Create the Factorio shell plus `prototypes/mir/` compiler namespace from `docs/architecture/module-boundaries.md`.
- [ ] Convert root Factorio files into thin stage wrappers without changing behavior.
- [ ] Add `stage/`, `core/`, `platform/`, `domain/`, and `legacy/` as the first migration shell.
- [ ] Keep existing public module paths as legacy shims where that reduces target-line backport friction.
- [ ] Add or formalize schema validators for facts, candidates, decisions, stream specs, manifests, claims, fixtures, and migrations.
- [ ] Promote the capability resolver contract to the public 3.0 architecture boundary.
- [ ] Add `DecisionRecord` v1 validation.
- [ ] Add `StreamSpec` v1 validation.
- [ ] Add policy overlay schema validation.
- [ ] Add stable ID helper tests.
- [ ] Confirm alpha 1 adds no new gameplay behavior.

### v3.0.0 Alpha 2: Current Behavior Through Compiler Phases

- [ ] Move old generator, recipe-matching, compat-profile, and report-row code behind legacy shims before deeper rewrites.
- [ ] Move existing explicit stream generation behind validated `StreamSpec` records without changing released technology IDs.
- [ ] Move Air Scrubbing clean-filter support through capability and policy records.
- [ ] Move owner, cap, lab, and loop diagnostics into report modules.
- [ ] Make the emission layer the only layer that mutates technology prototypes.
- [ ] Run report diffs proving no unexpected generated technology changes.

### v3.0.0 Alpha 3: Fact Registry V2

- [ ] Expand facts for items, fluids, entities, technologies, labs, machines, resources, modules, owners, and rule surfaces.
- [ ] Add entity-backed item and recipe links.
- [ ] Add loader and mining-drill facts.
- [ ] Add machine base-productivity facts.
- [ ] Add rule-surface facts for caps, modules, beacons, recyclers, and labs.

### v3.0.0 Alpha 4: Capability Registry

- [ ] Keep recipe productivity separate from native modifiers.
- [ ] Add machine manufacturing capability.
- [ ] Add loader manufacturing capability as report-first unless an existing stream owns the target.
- [ ] Add mining-drill manufacturing capability as report-first unless an existing stream owns the target.
- [ ] Add native modifier capability as observe-only by default.
- [ ] Add science/lab integration capability as a hard researchability gate.

### v3.0.0 Beta 1: Graph And Safety

- [ ] Add or formalize recipe graph, technology graph, science graph, resource-chain graph, and loop-risk graph outputs.
- [ ] Expand negative fixtures for self-return, barrel/container return, cleaning, catalyst, recycling, voiding, matter/transmutation, hidden recipes, zero caps, external owners, loader decoys, drill decoys, and lab incompatibility.
- [ ] Require report diff review for broad classifier or policy changes.
- [ ] Add performance budgets for large modpacks and verbose diagnostics.

### v3.0.0 Beta 2: Compatibility Proof

- [ ] Revalidate Air Scrubbing through the new compiler path.
- [ ] Revalidate ATAN Nuclear Science as a science/lab fixture.
- [ ] Revalidate AAI Loaders as a loader manufacturing report or existing belt-stream proof.
- [ ] Revalidate Big Mining Drill as a drill manufacturing report or existing drill-stream proof.
- [ ] Add ore-crushing productivity only if exact recipe IDs, owner checks, loop checks, cap checks, lab checks, and manifest rows pass.

### v3.0.0 Beta 3: Docs, Claims, And Migrations

- [ ] Keep compatibility claim manifests synchronized with public docs.
- [ ] Keep generated stream manifests synchronized with emitted technologies.
- [ ] Write migration notes for any changed generated technology IDs.
- [ ] Refresh README for the 3.0 compatibility compiler model.
- [ ] Keep ADRs current when architectural decisions change.

### v3.0.0 Release Gate

- [x] Run `.\scripts\Invoke-MIRValidation.ps1 -StaticOnly`.
- [x] Run Factorio `2.1` runtime validation.
- [x] Run the full-profile targeted release gate with `-NoGitPull` and
  package output under `build/`.
- [x] Run `git diff --check`.
- [x] Review final planner report diffs.
- [x] Confirm package hygiene excludes docs, fixtures, scripts, task ledgers,
  and generated artifacts that do not belong in the mod zip.
- [x] Confirm public docs do not claim broad K2, Bob's, Angel's, Space
  Exploration, Pyanodons, AAI, native modifier, cap, beacon, recycler, or
  runtime productivity support beyond fixture-backed behavior.

## Post-3.0 Target-Line Backports

Do not reconstruct old releases commit-by-commit. A target-line release is a
compatibility port of a tested current-line snapshot.

- [ ] Use `docs/maintainer/backporting.md` as the source of truth for the locked version-line mapping.
- [ ] Use `docs/archive/2.x/legacy-backport-cadence.md` as the source of truth for target order, support class, and source snapshot language.
- [ ] Treat every lower line as a separate target-line port, not a wholesale `3.0.0` backport.
- [x] Upload `v2.3.0` as the first Factorio `2.0` port of the MIR 3 architecture from the validated `legacy` branch package.
  Current release package: `dist/more-infinite-research_2.3.0.zip`,
  SHA-256 `84287C5ACD047F6A3E1A6EDD568DEF313C13403CD35BB165CA399F4B02E19133`.
- [x] After Mod Portal upload, verify it lists `2.3.0` for Factorio `2.0`,
  tag the GitHub release point, mark `.mir/branches.yml` as `published`, and
  treat the uploaded zip as immutable.
- [x] Do not rebuild `2.3.0` after upload; any changed payload becomes
  `2.3.1`.
- [x] Bring only portable lessons from `2.3.0` back into `dev`: validation
  runner improvements, package hygiene checks, target manifest improvements,
  report-diff tooling, deterministic ordering fixes, generic platform-adapter
  fixes, clearer diagnostics, docs corrections, release-process hardening,
  shared 2.1-valid fixtures, and shared compiler bug fixes.
- [ ] Do not bring Factorio `2.0` metadata, lower dependency floors, disabled
  `2.1` surfaces, 2.0 release wording, or lower-target compromises back into
  default Factorio `2.1` behavior.
- [ ] Do not cut `3.0.1` unless the current Factorio `2.1` line has a serious
  load failure, broken migration, generated-ID problem, package hygiene issue,
  materially wrong upload, or already-validated critical compatibility fix.
- [ ] Accumulate normal portable lessons for `3.0.5` after `2.3.0` is
  published, `1.1` is published or has produced clear lessons, the `1.0` /
  `0.18` bridge is decided, and community feedback has had a short window.
- [x] Release `v1.9.3` as the first Factorio `1.1` compatibility port only after target-line implementation and binary validation.
  Ring 2 posture: no Space Age, Quality, Recycler, Elevated Rails, cargo
  modifiers, recipe productivity, `storage`, or Factorio `2.x` dependency
  syntax leakage. Prove target-valid science packs, effects,
  `max_level`, `count_formula`, old recipe schema, package hygiene, and
  compatibility-port release wording against a Factorio `1.1` binary.
  Current RC package: `dist/more-infinite-research_1.9.3.zip`, SHA-256
  `1723C10FEDD9A12003052991CC7574F1F6BF4E4ABC506F0323571DF680C0444B`, size
  `298759` bytes, `121` entries, `0` forbidden entries. Static validation and
  Factorio `1.1` binary validation passed on 2026-07-10 with
  `D:\Programs\Factorio\1.1\bin\x64\factorio.exe`, including the packaged zip
  smoke check and reduced `1.1` fixture gate. Factorio `1.1.110` rejected
  `change-recipe-productivity`, so recipe productivity remains a documented
  target-line exclusion.
- [ ] Release `v1.8.0` as the Factorio `0.18` bridge compatibility port from the MIR 3 source anchor plus portable `2.3.0` and `1.9.3` lessons.
  Current bridge candidate package: `dist/more-infinite-research_1.8.0.zip`,
  SHA-256 `A3CDFCCDE640C33D6A75AEAF957695EFE0D4DE6928691502D88B5D9479284E0D`,
  size `301566` bytes, `121` entries, `0` forbidden entries. Static validation
  passed, Factorio `1.0` bridge validation passed with
  `D:\Programs\Factorio\1.0\bin\x64\factorio.exe`, and the public dist archive
  content matches the runtime-validated archive. A matching Factorio `0.18`
  binary is still required before final publication. The bridge uses target-era
  base technology art only; it does not package newer Factorio 1.1+ technology
  constant badge graphics. Native effect rows carry explicit icon metadata,
  and generated technology tiles now use visible target-era productivity,
  range, and speed badge overlays for the old UI.
- [ ] Release `v1.8.1` as the true Factorio `1.0` compatibility port only if the `0.18` bridge does not cover the public `1.0` release shape.
- [ ] Release `v1.7.0`, `v1.6.0`, and `v1.5.0` as reduced native-infinite editions for Factorio `0.17`, `0.16`, and `0.15` only after target binary proof.
- [ ] Release `v1.4.0`, `v1.3.0`, and `v0.12.0` as archive finite-ladder reconstructions only after target binary proof.
- [ ] Release `v0.11.0` through `v0.6.0` as museum/discovery builds only after target binary and base-file discovery.
- [ ] Validate each target-line release with a matching target Factorio binary when available, and document any missing validation in release notes.

## Companion Mod Backlog

These are intentionally not `v2.0.5` or `v2.1.0` MIR core work.

- [ ] Cold Chain / CryoPants: freezer chest, freeze/thaw recipes, refrigerated transport, freshness penalty.
- [ ] Advanced Agriculture: greenhouse, off-world fruit, heating constraints, artificial soil loops.
- [ ] Advanced Quality Research: higher quality module tiers, quality odds tuning, quality-based spoilage.
- [ ] Quality module enrichment research: prototype/module-tier spike only; do not implement as runtime module mutation in core MIR.
- [ ] Space Platform Engines: efficient thruster, high-thrust thruster, related platform entities.
- [ ] Bio Resource Experiments: super-bacteria, biter egg accelerator, reverse spoilage challenges.
- [ ] More Infinite Logistics companion decision: split if pump/pipeline/entity unlocks grow beyond MIR's research-scaling identity.

## Rejected For Now

- [ ] True infinite thruster thrust research, unless Factorio exposes a native technology modifier.
- [ ] Runtime platform speed mutation as a fake thrust bonus.
- [ ] Infinite quality odds research through runtime module mutation.
- [ ] Refrigeration by scanning every spoilable stack in every inventory.
- [ ] Per-tick farm, belt, lab, container, platform, or item-stack scanning.

## Recurring Release Checklist

Run this before every release candidate:

- [ ] `git status --short --branch`
- [ ] `rg "data.raw.tool|tool_exists|has_tool|PACKS_ALL" prototypes`
- [ ] `rg "on_tick" control prototypes`
- [ ] `rg "icon_mipmaps" prototypes`
- [ ] `.\scripts\Build-MIRPackage.ps1`
- [ ] `.\scripts\Invoke-MIRValidation.ps1 -StaticOnly`
- [ ] `.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"`
- [ ] `.\scripts\Invoke-MIRExtendedTests.ps1 -Tier Static,Runtime,AuditSmoke -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe" -FailFast`
- [ ] `.\scripts\Invoke-MIRExtendedTests.ps1 -Tier Static,Runtime,AuditSmoke -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe" -FailFast -FailOnAuditFailures`
- [ ] Manual-scenario, lockfile-resume, and profile-stub smoke paths for the compatibility audit tooling.
- [ ] `.\scripts\Test-MIRBranchPolicy.ps1`
- [ ] `git diff --check`
- [ ] Load the release zip from a normal Factorio mods folder.
- [ ] Record validation results in the active release validation record under `docs/releases/`.
- [ ] Commit docs, code, changelog, and package together for the tested candidate.

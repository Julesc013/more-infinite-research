# M.I.R. TODO

Updated: 2026-07-10

This is the active task list for MIR 3.0.5 and later. It should contain future
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
- MIR 1.9.3, 1.8.0, 1.8.1, and 1.7.0 are published target-line evidence.
- MIR 3.0.5 is the active Factorio 2.1 convergence and compatibility-hardening
  release. It remains based on the modern `dev` implementation.
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

Use `.mir/convergence.yml` and `docs/releases/3.0.5-convergence-plan.md` for
active release scope, product boundaries, rationale, and high-level
explanations. Use `docs/releases/3.0.5-release-checklist.md` and
`docs/releases/3.0.5-validation-summary.md` for the active gate and evidence.
Treat `docs/releases/3.0.0-plan.md` as historical baseline context. Use
`docs/archive/2.x/completed-task-ledger.md` for the historical completed task
ledger. Use `docs/archive/2.x/post-2.0-feature-plan.md` for the deeper idea
archive, `docs/archive/2.x/legacy-backport-cadence.md` for historical older-line
backport planning, and `docs/maintainer/backporting.md` for the locked
post-`2.2.0` target-line policy. Use `changelog.txt` as the authoritative
past-change ledger for shipped player-facing changes.

## Working Rules

- Target `dev` for MIR 3.0.5 Factorio `2.1` development.
- Treat MIR 3.0.5 as bounded convergence and compatibility hardening, not a
  historical implementation merge or broad gameplay release.
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
- Keep the 3.0.5 convergence plan, checklist, and validation summary
  synchronized with this file and `changelog.txt` while 3.0.5 is active.
- Treat the compatibility planner as the contract between prototype discovery,
  owner classification, validation, mutation, and diagnostics.

## Archived Historical Ledgers

- Historical completed task ledger: `docs/archive/2.x/completed-task-ledger.md`
- Historical 2.2 feature intake: `docs/archive/2.x/2.2.0-feature-intake.md`
- Historical post-2.0 feature plan: `docs/archive/2.x/post-2.0-feature-plan.md`
- Historical backport cadence: `docs/archive/2.x/legacy-backport-cadence.md`

## MIR 3 Current Line

MIR 3.0.0 is the published architecture baseline. MIR 3.0.5 converges portable
lessons from the released target lines while keeping Factorio 2.1 behavior and
the modern compiler authoritative. Use `.mir/convergence.yml` and
`docs/compatibility/backport-ledger.md` for the active behavior contract.

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

### Historical 3.0.0 Alpha And Beta Work

The completed architecture transition is represented by the shipped tree,
3.0.0 release records, ADRs, and
`docs/archive/2.x/completed-task-ledger.md`. The obsolete unchecked alpha/beta
intake was removed from this active future-work ledger; git history remains the
source for its original wording.

### v3.0.5 Convergence Gate

- [x] Freeze the modern baseline at `pre-3.0.5-synthesis` and enable rerere.
- [x] Record 1.7.0 release evidence and classify accepted behavior in
  `.mir/convergence.yml`.
- [x] Port science-prerequisite reachability as a generic compiler invariant.
- [x] Centralize target capabilities and generate the Lua profile view.
- [x] Select `storage` or `global` through an explicit target-owned adapter.
- [x] Persist grouped runtime results, including interrupted/incomplete runs.
- [x] Split reduced settings-surface evidence from settings-profile codec
  behavior.
- [x] Make conditional weapon overlap removal depend on exact replacement
  coverage and preserve explicit existing choices.
- [x] Run the complete Factorio 2.1 base and Space Age suite after behavior
  synthesis.
- [x] Build and checksum the exact 3.0.5 candidate archive.
- [x] Record exact-dist evidence and a complete structured result summary.
- [ ] Tag and publish only after final manual review; do not rebuild verified
  bytes during publication.

## Post-3.0 Target-Line Backports

Do not reconstruct old releases commit-by-commit. A target-line release is a
compatibility port of a tested current-line snapshot.

- [x] Use `docs/maintainer/backporting.md` as the source of truth for the locked version-line mapping.
- [x] Use `docs/archive/2.x/legacy-backport-cadence.md` as the source of truth for target order, support class, and source snapshot language.
- [x] Treat every lower line as a separate target-line port, not a wholesale `3.0.0` backport.
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
- [x] Bring only portable lessons from `1.9.3` back into `dev`: target-line
  adapter seams, runtime state adapter usage, 1.1 binary validation profile
  improvements, package hygiene checks, stock target-era icon fallback policy,
  release documentation, and shared 2.1-valid fixture corrections.
- [x] Bring only portable lessons from `1.8.0` back into `dev`: immutable bridge
  release evidence, release documentation, reduced-line validation profile
  improvements, continuation locale-source handling, old-line modifier locale
  fallbacks, stock target-era icon fallback policy, and package hygiene notes.
- [x] Do not bring Factorio `2.0`, `1.1`, `1.0`, or `0.18` metadata, lower dependency floors, disabled
  `2.1` surfaces, 2.0 release wording, or lower-target compromises back into
  default Factorio `2.1` behavior.
- [x] Skip `3.0.1`; no emergency current-line defect required that release.
- [x] Accumulate normal portable lessons for `3.0.5` after `2.3.0` is
  published, `1.1` is published or has produced clear lessons, the `1.0` /
  `0.18` bridge is decided, and community feedback has had a short window.
- [x] Prepare and validate `v1.9.3` as the first Factorio `1.1` compatibility port after target-line implementation and binary validation.
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
- [x] Publish and record `v1.9.3`; the exact archive, tag, commit, and public
  status are recorded in `.mir/branches.yml`.
- [x] Release `v1.8.0` as the Factorio `0.18` bridge compatibility port from the MIR 3 source anchor plus portable `2.3.0` and `1.9.3` lessons.
  Published bridge package: `dist/more-infinite-research_1.8.0.zip`,
  SHA-256 `D785E6EBE7A72E6E9F01A3F89774A6AA30479430410447F603FEF1E0B9BD7B24`,
  size `300620` bytes, `121` entries, `0` forbidden entries. Static validation
  passed, Factorio `0.18` binary validation passed, Factorio `1.0` bridge
  validation passed with
  `D:\Programs\Factorio\1.0\bin\x64\factorio.exe`, and the public dist archive
  content matches the runtime-validated archive. The bridge uses target-era base
  technology art only; it does not package newer Factorio 1.1+ technology
  constant badge graphics, synthetic badge overlays, or unsupported native
  modifier icon metadata. Research productivity uses stock military science
  technology art as its main tile.
- [x] Release `v1.8.1` as the first maintained Factorio `1.0` compatibility
  port from the `1.9.3` source posture, proven `1.8.0` bridge lessons, and
  current dev portable fixes. Package candidate:
  `dist/more-infinite-research_1.8.1.zip`, SHA-256
  `B1622AB0BC6D72265842D698781DBE21B7286662E29FB6992057FBCFF87D8E29`,
  size `300526` bytes, `116` entries, `0` forbidden entries. Static
  validation passed, Factorio `1.0` binary validation passed with
  `D:\Programs\Factorio\1.0\bin\x64\factorio.exe`, and the public dist archive
  content matches the runtime-validated archive. Do not use `0.8.x` for
  Factorio `1.0`; `0.8.x` remains reserved for the later Factorio `0.8` museum
  line.
- [x] Release `v1.7.0` as the reduced native-infinite edition for Factorio
  `0.17` after exact-package validation against Factorio `0.17.79`.
- [ ] Release `v1.6.0` and `v1.5.0` as old-science native-infinite editions for
  Factorio `0.16` and `0.15` only after 3.0.5 convergence and target binary
  proof. Seed 0.16 from the 3.0.5 canonical source plus synthesized 1.7.0
  behavior, not by merging the 0.17 implementation wholesale.
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

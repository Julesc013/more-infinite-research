# M.I.R. TODO

Updated: 2026-07-17

This is the current executable queue for `dev`. Historical pre-consolidation queue text is preserved at `.mir/evidence/lower-wave/todo-2026-07-14-pre-consolidation.md`. `.mir/releases.json` is the canonical release ledger; branch, release-wave, distribution, queue, and promotion views must agree with it.

## Current Truth

- MIR 3.1.9 is the immutable Factorio 2.1 release; MIR 2.4.5 is the immutable Factorio 2.0 companion.
- MIR 1.9.4 and 1.8.2 are the immutable Factorio 1.1 and 1.0 releases.
- MIR 1.7.1 through 1.3.0 are published reduced or finite target projections for Factorio 0.17 through 0.13.
- MIR 0.12.0 through 0.6.0 are published finite archive or museum reconstructions whose corrected packages now include explicit target-matching `factorio_version` metadata.
- The modern `dev` root contains every accepted portable code, data, fixture, validation, documentation, determinism, process-lifecycle, and package-governance return from those target lines.
- Complete immutable source snapshots for published campaign versions remain under `.mir/target-lines/<version>/`, but active validation and assurance fingerprints exclude those archival trees unless the dedicated snapshot-integrity gate is running.
- The 44 tracked root distribution paths are bound by `.mir/distributions.json`. MIR 3.2.0 is explicitly a development candidate; the nonexistent 1.9.5 and not-yet-built final 2.5.0 archives are not distribution entries.
- Target-era metadata, API cuts, finite compiler implementations, and museum code remain isolated inside their snapshots and target branches. They are not modern Factorio 2.1 defaults.
- The lower-wave fixed-point audit found zero unreturned portable fixes, zero stale source locks, zero stale candidates, and zero branch divergence.
- MIR 3.2.0 verifier hardening, integrity-kernel work, modularization, optimization, fixtures, tests, and documentation are authorized on `dev`. MIR 2.5.0 begins only after the canonical 3.2.0 source freezes.

## Consolidation Gate

- [x] Import the aggregate feature, source-lock, qualification, seal, publication, balance, and branch evidence into `dev`.
- [x] Reconcile the 44 real tracked distribution paths under `dist/`; remove nonexistent 1.9.5 and provisional 2.5.0 rows and classify 3.2.0 as a development candidate.
- [x] Export each published tag's complete tracked code, data, tests, scripts, notes, docs, manifests, and evidence under `.mir/target-lines/`.
- [x] Preserve the modern root as the only active Factorio 2.1 implementation.
- [x] Consolidate one source-faithful changelog section for every real version in the 44-file distribution inventory.
- [x] Complete the copy-ready release, feature, test, lesson, reliability, optimization, and follow-up document.
- [x] Validate every snapshot tree and all 46 root distributions against their immutable or explicitly classified source and recorded hash.
- [x] Run docs governance, manifest, static, deterministic-package, and forbidden-entry validation.
- [x] Correct the shared museum metadata generator, rebuild and exact-binary requalify all seven 0.x archives, replace their GitHub tags/releases, and refresh the `dev` snapshots and distribution inventory.
- [ ] Rerun the Factorio 2.1 runtime catalog against the changelog-updated development package when a Factorio 2.1 binary is available. The released 3.1.9 ZIP retains accepted 102-of-102 evidence, but that is not a new exact-package run.
- [x] Commit and push the complete consolidation to `dev`.

## Remaining Human And External Gates

- [ ] Perform maintainer visual technology-tree, icon, locale-fit, save-UI, and balance review for 1.7.1 through 0.6.0. Automated locale and balance gates passed; manual review remains `PENDING-MAINTAINER`.
- [ ] Upload 1.9.4, 1.8.2, and 1.7.1 through 1.3.0 to the Factorio Mod Portal when `MOD_UPLOAD_API_KEY` is available. Do not convert missing credentials into a passing status.
- [ ] Upload the corrected 0.12.0 through 0.6.0 archives to the Factorio Mod Portal and record the service's acceptance or rejection without treating GitHub publication as portal proof.
- [ ] Acquire complete Angel, Space Exploration, and Pyanodon dependency closures before making stronger compatibility claims. Inventory or a zero-root load is not evidence.

## Reliability And Robustness Backlog

- [x] Add an automated integrity gate for `.mir/target-lines/index.json` so every snapshot must reproduce its recorded Git root tree and exact distribution SHA-256.
- [x] Keep validation and assurance fingerprints scoped to the active modern root; development-only immutable snapshots do not become current-package compatibility evidence.
- [ ] Move full historical source snapshots to release artifacts or an archival repository while retaining only commit, tree, and archive hashes in the active repository.
- [ ] Keep every runtime process owned by explicit timeout, exit wait, and process-tree cleanup.
- [ ] Keep scenario selection capability-driven and require exact manifest equality before runtime execution.
- [ ] Keep configuration-change scenarios two-phase and preserve exact initial and changed mod sets in evidence.
- [x] Keep package and harness fingerprints checkout-line-ending invariant.
- [x] Keep accepted compilation plans unpublished until all authoritative validation completes.
- [x] Keep generated graph traversal iterative, deterministic, cycle-strict, and reachability-strict.
- [x] Keep visible settings limited to positively supported emitted target capabilities.
- [ ] Keep target CLI flags, log grammar, loaded-map markers, exit markers, save addressing, and deployment routes capability-owned.
- [ ] Keep exact release ZIPs immutable after sealing and validate the public bytes rather than rebuilding them.

## Current 3.2 Campaign Gate

- [x] Authorize MIR 3.2 implementation on `dev`.
- [x] Harden plan, capsule, trust, freshness, closure, bundle, and seal verification before release qualification.
- [x] Complete generic technology-effect integrity and whole-graph SCC planning before release qualification.
- [x] Complete bounded performance telemetry and bind its static policy gate into the full profile.
- [ ] Establish the 3.1.9 normalized behavior-equivalence export and approved-delta manifest before the final source freeze.
- [ ] Raise the synthetic scale campaign from its current 1,000 recipes, 1,000 technologies, and 10,000 effects to the 100,000-node stress targets without weakening deterministic or diagnostic-size assertions.
- [ ] Split remaining planning-time icon construction and hidden singleton indexes into an explicit snapshot-scoped compiler context.
- [ ] Freeze canonical 3.2 source before creating the final 2.5.0 backport candidate.
- [ ] Begin any later campaign with `git fetch --all --tags --prune`.
- [ ] Reconcile `dev`, `main`, release tags, `.mir/branches.yml`, `.mir/release-wave.yml`, and all open human gates before choosing new scope.
- [ ] Preserve 3.1.9 behavior and stable identities unless a new release plan explicitly authorizes a change.

## Recurring Gate

- [ ] `git status --short --branch`
- [ ] `git diff --check`
- [ ] `./scripts/Format-MIRMarkdown.ps1 -Check`
- [ ] `./scripts/Invoke-MIRValidation.ps1 -StaticOnly`
- [ ] `./scripts/Test-MIRPublishedSnapshotIntegrity.ps1`
- [ ] Run Factorio 2.1 exact-package base and Space Age checks.
- [ ] Run the full declared Factorio 2.1 scenario catalog when package-visible source changes.
- [ ] Verify deterministic package construction and forbidden-entry hygiene.
- [ ] Verify every affected immutable distribution hash.
- [ ] Complete any required interactive review without rebuilding sealed bytes.

# M.I.R. TODO

Updated: 2026-07-24

This is the current executable queue for `dev`. Historical pre-consolidation queue text is preserved at `.mir/evidence/lower-wave/todo-2026-07-14-pre-consolidation.md`. `.mir/releases.json` is the canonical release ledger; branch, release-wave, distribution, queue, and promotion views must agree with it.

## Current Truth

- MIR 3.1.9 is the immutable Factorio 2.1 release; MIR 2.4.9 is the immutable Factorio 2.0 companion.
- MIR 1.9.4 and 1.8.2 are the immutable Factorio 1.1 and 1.0 releases.
- MIR 1.7.1 through 1.3.0 are published reduced or finite target projections for Factorio 0.17 through 0.13.
- MIR 0.12.0 through 0.6.0 are published finite archive or museum reconstructions whose corrected packages now include explicit target-matching `factorio_version` metadata.
- The modern `dev` root contains every accepted portable code, data, fixture, validation, documentation, determinism, process-lifecycle, and package-governance return from those target lines, including the completed 2.4.9 campaign.
- Complete immutable source snapshots for published campaign versions remain under `.mir/target-lines/<version>/`, but active validation and assurance fingerprints exclude those archival trees unless the dedicated snapshot-integrity gate is running.
- The 45 tracked root distribution paths are bound by `.mir/distributions.json`: 44 tagged releases plus the MIR 3.2.0 development candidate. The nonexistent 1.9.5 and not-yet-built final 2.5.0 archives are not distribution entries.
- Target-era metadata, API cuts, finite compiler implementations, and museum code remain isolated inside their snapshots and target branches. They are not modern Factorio 2.1 defaults.
- The lower-wave fixed-point audit found zero unreturned portable fixes, zero stale source locks, zero stale candidates, and zero branch divergence.
- MIR 3.2.0 verifier hardening, integrity-kernel work, modularization, optimization, fixtures, tests, and documentation are authorized on `dev`. MIR 2.5.0 begins from the 2.4.9 baseline only after the canonical 3.2.0 source freezes.
- The former `3976BC...` development package and its 125-test result are historical checkpoint evidence. The replacement 3.2.0 package is rebuilding and is not release-qualified.

## Consolidation Gate

- [x] Import the aggregate feature, source-lock, qualification, seal, publication, balance, and branch evidence into `dev`.
- [x] Reconcile the 45 real tracked distribution paths under `dist/`; remove nonexistent 1.9.5 and provisional 2.5.0 rows and classify 3.2.0 as a development candidate.
- [x] Export each published tag's complete tracked code, data, tests, scripts, notes, docs, manifests, and evidence under `.mir/target-lines/`.
- [x] Preserve the modern root as the only active Factorio 2.1 implementation.
- [x] Consolidate one source-faithful changelog section for every real version in the 45-file distribution inventory.
- [x] Complete the copy-ready release, feature, test, lesson, reliability, optimization, and follow-up document.
- [x] Validate every snapshot tree and all 45 root distributions against their immutable or explicitly classified source and recorded hash.
- [x] Run docs governance, manifest, static, deterministic-package, and forbidden-entry validation.
- [x] Correct the shared museum metadata generator, rebuild and exact-binary requalify all seven 0.x archives, replace their GitHub tags/releases, and refresh the `dev` snapshots and distribution inventory.
- [x] Rerun the Factorio 2.1 runtime catalog against the exact 3.2.0 development package; the local full profile passed all 125 declared F0-F4 tests.
- [x] Commit and push the complete consolidation to `dev`.

## MIR 2.4.x Closeout

- [x] Publish MIR 2.4.9 from tag `7ebe93029695bbf809a15a14c6540530738a9e62` and freeze archive SHA-256 `B5503F94D04624F65462CC275FB6AA71A8CE93075F732DF498F6D73AD255F978`.
- [x] Return the exact 2.4.9 distribution, approved delta, automated qualification, paired performance evidence, release notes, stability record, and complete tagged source snapshot to `dev`.
- [x] Confirm that the portable technology-effect sanitation, Space Exploration removed-recipe fix, steel-productivity ownership, reset removal, locale system, and verification improvements already exist in the active 3.2 implementation.
- [x] Keep Factorio 2.0 metadata, dependency floors, API cuts, and release wording inside the immutable snapshot and target branches rather than overlaying them onto the Factorio 2.1 root.
- [x] Record that maintainer-directed publication occurred without a recorded package-focused manual attestation or protected qualification; do not represent those missing gates as passed.

## Remaining Human And External Gates

- [ ] Perform maintainer visual technology-tree, icon, locale-fit, save-UI, and balance review for 1.7.1 through 0.6.0. Automated locale and balance gates passed; manual review remains `PENDING-MAINTAINER`.
- [ ] Upload 1.9.4, 1.8.2, and 1.7.1 through 1.3.0 to the Factorio Mod Portal when `MOD_UPLOAD_API_KEY` is available. Do not convert missing credentials into a passing status.
- [ ] Upload the corrected 0.12.0 through 0.6.0 archives to the Factorio Mod Portal and record the service's acceptance or rejection without treating GitHub publication as portal proof.
- [ ] Acquire complete Angel, Space Exploration, and Pyanodon dependency closures before making stronger compatibility claims. Inventory or a zero-root load is not evidence.
- [x] Enforce exact per-campaign sanitation budgets with zero unreviewed external prunes and `REVIEW_REQUIRED` mismatch handling.

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
- [x] Establish the 3.1.9 normalized behavior-equivalence export and approved-delta manifest before the final source freeze.
- [x] Raise the synthetic scale campaign to 100,000 canonical recipes, technologies, effects, and graph edges while preserving deterministic fingerprints and bounded diagnostics.
- [x] Move compiler snapshots and indexes into explicit snapshot-scoped context ownership and complete the governed design, lifecycle, policy, synthesis, and interaction-campaign sequence.
- [x] Record the historical exact 3.1.9-to-3.2.0 upgrade and local 125-test F0-F4 checkpoint against candidate SHA-256 `3976BCF18269FC2F11BCFF2A24D4D7830C75284FDAC6DD5C5FA57AC94C5FCA2C`.
- [x] Regenerate the seven-scenario approved delta and expanded five-archetype upgrade/configuration-change evidence against candidate `C4B08D60...` on Factorio 2.1.11.
- [x] Establish and bind the qualified 3.1.9 runtime performance regression evidence required directly by the revised F4 profile.
- [x] Complete the local exact-candidate Factorio 2.1.11 full profile; all 128 machine-verifiable tests pass and only `manual.release-review` remains failed locally.
- [x] Raise the dependency floor to Factorio 2.1.11, correct the four governed native-owner stream policies, and build C5.
- [x] Expand the 3.1.9-to-3.2.0 upgrade harness across base, Space Age native-owner, automatic-family, base-continuation, and mod-set configuration-change archetypes.
- [x] Complete bounded C7 architectural convergence from the unqualified C6 foundation without adding gameplay scope.
- [x] Complete the governed C8 compiler-platform overhaul from the unqualified C7 foundation and freeze its exact package-source and archive identities.
- [x] Complete the governed C9 deterministic compiler-boundary overhaul from the unqualified C8 foundation and freeze its exact package-source and archive identities.
- [x] Complete the governed C10 compiler contract-closure overhaul from the unqualified C9 foundation and freeze its exact package-source and archive identities.
- [x] Correct C10's exact-singleton candidate-seed ambiguity defect as C11 and freeze its exact package-source and archive identities.
- [x] Remove C11's redundant transient TechnologyCatalog construction, generate packaged defaults from canonical Lua, and freeze C12 without widening the technology set.
- [x] Profile C12's final catalog construction, apply bounded trusted copy-on-write construction, and freeze exact C13 without changing technology identities or selections.
- [x] Replace C13 with exact C14 after full static qualification found one packaged changelog line above the enforced 132-character limit.
- [x] Make full-plan execution fail closed on preflight exceptions, incomplete result sets, and unexpected result rows; retain the first run as 124/124 directly dispatched development passes rather than misreporting 129/129.
- [x] Pass all five exact C14 upgrade archetypes, all nine targeted ecosystem repair smokes, the representative BZ plus Space Age scenario, and the seven-scenario 221-row approved delta.
- [x] Retire the obsolete Krastorio Spaced Out sanitation prune expectation after the exact current closure passed with zero external repairs, then pass the paired closure smoke.
- [x] Run all 72 governed C14-Q3 paired performance invocations and fix ordered telemetry-map evaluation so all 38 real counter-bound checks are evaluated correctly.
- [x] Make hosted validation represent an all-reuse plan with one explicit no-op matrix row while retaining the aggregate evidence gate as the only pass authority.
- [ ] Resolve C14's paired 3.1.9 performance-regression failure without weakening the declared gate.
- [ ] Run all final-candidate-bound automated work from the immutable C14 package source and current qualification contract.
- [ ] Complete the exact-final-candidate package manual attestation, then complete the separate public-presentation review.
- [ ] Supply the missing exact Pyanodon and legacy Space Exploration dependency closures before strengthening those compatibility claims.
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

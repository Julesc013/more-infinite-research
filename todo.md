# M.I.R. TODO

Updated: 2026-07-28

This is the current executable queue for `dev`. Historical pre-consolidation queue text is preserved at `.mir/evidence/lower-wave/todo-2026-07-14-pre-consolidation.md`. `.mir/releases.json` is the canonical release ledger; branch, release-wave, distribution, queue, and promotion views must agree with it.

## Current Truth

- MIR 3.2.1 is the tagged and Mod Portal-published Factorio 2.1 baseline. Protected run 30229114461 is retained as an honestly failed historical attempt and does not move or requalify that immutable tag. MIR 2.4.9 remains the immutable published Factorio 2.0 baseline until 2.5.0 qualifies.
- MIR 1.9.4 and 1.8.2 are the immutable Factorio 1.1 and 1.0 releases.
- MIR 1.7.1 through 1.3.0 are published reduced or finite target projections for Factorio 0.17 through 0.13.
- MIR 0.12.0 through 0.6.0 are published finite archive or museum reconstructions whose corrected packages now include explicit target-matching `factorio_version` metadata.
- The modern `dev` root contains every accepted portable code, data, fixture, validation, documentation, determinism, process-lifecycle, and package-governance return from those target lines, including the completed 2.4.9 campaign.
- Complete immutable source snapshots for published campaign versions remain under `.mir/target-lines/<version>/`, but active validation and assurance fingerprints exclude those archival trees unless the dedicated snapshot-integrity gate is running.
- The 47 tracked root distribution paths are bound by `.mir/distributions.json`: 45 earlier tagged releases, exact MIR 3.2.1 retained as the Mod Portal-published tagged baseline, and the exact unreleased MIR 3.2.2 hotfix candidate. The nonexistent 1.9.5 and not-yet-authorized dev-line 2.5.0 archive are not distribution entries.
- Target-era metadata, API cuts, finite compiler implementations, and museum code remain isolated inside their snapshots and target branches. They are not modern Factorio 2.1 defaults.
- The lower-wave fixed-point audit found zero unreturned portable fixes, zero stale source locks, zero stale candidates, and zero branch divergence.
- Exact C20 was tagged and published as MIR 3.2.0 from `main`. Its GitHub asset digest matches the immutable recorded ZIP; the longer, manual, protected, and seal gates were not completed before maintainer-directed publication and remain recorded as assurance exceptions rather than passes.
- MIR 3.2.1 C21 is the exact tagged and Mod Portal-published planet-discovery hotfix with all 129 local no-reuse rows passed. Protected run 30229114461 is reconciled as historical failed evidence and does not qualify or move the immutable tag. MIR 3.2.2 C24 is the frozen Py finalizer-order and affected-save planet-recovery hotfix candidate: exact 2.1.8 floor smokes, 2.1.12 Base and Space Age loads, the exact 15-mod Py closure, direct six-row upgrade matrix, paired performance, full static validation, and hosted MIR/Branch Policy pass. Manual, full no-reuse, protected, seal, promotion, and tag gates remain. MIR 2.5.0 P9 is the deterministic Factorio 2.0 projection of final C24: exact Base and official Space Age loads, the exact 11-mod Py 2.0 closure, the direct 2.4.9 upgrade matrix, the 319-row approved delta, and all six paired performance lanes pass; final dual-parent reconstruction and full/manual/protected release gates remain.

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
- [x] Replace C14 with exact C15 after the K2SO science-progression playtest defect and freeze its exact package identity.
- [x] Make full-plan execution fail closed on preflight exceptions, incomplete result sets, and unexpected result rows; retain the first run as 124/124 directly dispatched development passes rather than misreporting 129/129.
- [x] Pass all five exact C14 upgrade archetypes, all nine targeted ecosystem repair smokes, the representative BZ plus Space Age scenario, and the seven-scenario 221-row approved delta.
- [x] Retire the obsolete Krastorio Spaced Out sanitation prune expectation after the exact current closure passed with zero external repairs, then pass the paired closure smoke.
- [x] Run all 72 governed C14-Q3 paired performance invocations and fix ordered telemetry-map evaluation so all 38 real counter-bound checks are evaluated correctly.
- [x] Run all 72 governed C15 paired performance invocations, preserve the exact failed result, and isolate repeated catalog validation and fingerprinting as the fixed small-profile cost.
- [x] Replace rejected C15 with exact C16 after the fixed-cost compiler performance correction, preserving all technology identities, selections, effects, science, prerequisites, ownership, settings, and sanitation across the seven governed runtime exports.
- [x] Pass the focused C16 formal paired performance campaign without changing budgets: all ten runtime and compiler-phase lanes passed, with deterministic work-volume counters enforcing zero trusted-assertion canonicalizations, full catalog snapshots, and full TechnologyDesign copies.
- [x] Make hosted validation represent an all-reuse plan with one explicit no-op matrix row while retaining the aggregate evidence gate as the only pass authority.
- [x] Resolve C15's inherited paired 3.1.9 performance-regression failure in C16 without weakening the declared gate.
- [x] Create C17 from C16 by enabling every shipped technology toggle by default while preserving explicit risk classification, top-of-list ordering, and duplicate-safe localized warnings.
- [x] Create C18 from C17 with bounded Space Age productivity streams for nutrients and capture bot rockets, tiered ice/space-platform effects, and explicit pentapod egg coverage.
- [x] Create C19 from C18 by adding the final packaged changelog date, rebuild deterministically, and freeze archive SHA-256 `6592D46C2F3F293770A69C21A59A4CB7A9012D759F2E6D078E62F26BA9BBA6C6`.
- [x] Run fast release-authority, documentation, static, composition, and deterministic-package validation for exact C19 before staging it on `main`.
- [x] Preserve C19 as rejected evidence after its long validation exposed the post-compile prerequisite-rewire graph mismatch.
- [x] Create C20 from C19 by journal-verifying competing technology rewires, freshly qualifying the realized graph, and fixing competing-productivity preparation.
- [x] Run focused replacement, rollback, multi-replacement, Base integrity, static, documentation, composition, and deterministic-package validation for exact C20.
- [x] Record that the longer exact-C20 validation campaign was not completed before maintainer-directed publication; do not relabel earlier candidate evidence as exact C20 evidence.
- [x] Tag exact C20 as `3.2.0`, publish the recorded ZIP without rebuilding, and verify the GitHub asset digest against the canonical archive SHA-256.
- [x] Create exact C21 by resolving `unlock-space-location` across concrete planet prototypes and preserve its deterministic emergency archive.
- [x] Reconcile C21 protected run 30229114461 as historical failed evidence without moving the immutable `3.2.1` tag or misrepresenting the absent seal.
- [x] Pass C24 exact 2.1.8 floor smokes, 2.1.12 Base and Space Age loads, the direct six-row 3.2.1 upgrade, paired performance, deterministic packaging, full static validation, and hosted MIR/Branch Policy.
- [x] Pass the exact real 15-mod Py 2.1 closure with `casting-gear` and its dangling `casting-mk02` unlock absent, all valid effects retained, and zero external sanitation; retain the synthetic one-row stale-unlock repair proof.
- [x] Focused-rerun space-age-scripted-runtime-disable-restoration on exact C24 and retain its portable passing summary.
- [x] Correct the Big Mining Drill validation harness to distinguish its reviewed explicit stream effect from the automatic provider's fail-closed progression-span review; the exact scenario passes without changing C24 bytes.
- [ ] Complete exact C24 differential manual review, one definitive no-reuse plan, protected qualification, schema-4 seal, and promotion check.
- [ ] Fast-forward `main`, verify immutable C24 bytes, push annotated tag `3.2.2`, and close issue #35 with the exact tested closure and package identity.
- [ ] Run all candidate-bound automated work required by any later package candidate before its release.
- [ ] Complete exact-candidate manual and public-presentation review for any later package candidate before its release unless a new maintainer decision explicitly records otherwise.
- [ ] Retain only the narrow exact-Py startup-integrity claim for C24/P9; broader full-Py and legacy Space Exploration claims require separate complete closures and evidence.
- [x] Build deterministic P9 from immutable 2.4.9 and final C24 package semantics through the explicit Factorio 2.0 capability adapters; pass focused static, synthetic, exact Base/Space Age, direct upgrade, approved-delta, and paired-performance gates.
- [ ] After tag `3.2.2` exists, update the immutable source-tag authority, reconstruct P9 twice with target-first/source-second parent order, and advance only `tmp/2.0`.
- [x] Pass the independent exact 11-mod Py 2.0 closure on Factorio 2.0.77 with the missing recipe and dangling unlock absent and zero unreviewed external sanitation.
- [x] Advance the P9 qualification-only checkpoint to Q4 without changing package bytes: port the current assurance fixes, isolate the Factorio 2.0 capability fixture context, and omit the engine-invalid parameter-recipe fixture from the 2.0 campaign.
- [ ] Resolve the strict P9 100,000-technology randomized-insertion comparison: coverage, generation, final graph, and in-memory graph fingerprints are stable, while the compiler qualification fingerprint still differs. Identify and correct the order-sensitive authority input; do not weaken or remove the comparison.
- [ ] Complete P9 manual review, the definitive no-reuse plan, protected qualification, schema-4 seal, and promotion check.
- [ ] Fast-forward `legacy`, verify immutable P9 bytes, and push annotated tag `2.5.0`.
- [x] Lock the P9 target-first/source-second reconstruction manifest and hash every deterministic reconstruction-receipt field independently of its observation timestamp.
- [ ] Begin the 3.3/2.6 semantic-platform program only after immutable `3.2.2` and `2.5.0` tags exist and their behavioral baselines are frozen.
- [ ] Begin any later campaign with `git fetch --all --tags --prune`.
- [ ] Reconcile `dev`, `main`, release tags, `.mir/branches.yml`, `.mir/release-wave.yml`, and all open human gates before choosing new scope.
- [ ] Preserve 3.1.9 behavior and stable identities unless a new release plan explicitly authorizes a change.

## MIR 3.3 And 2.6 Platform Backlog

The canonical future architecture and phased acceptance criteria are in docs/architecture/3.3-2.6-semantic-platform-roadmap.md. None of these items may change C24 or P9 package bytes.

- [ ] Freeze exact 3.2.2 and 2.5.0 semantic exports, package trees, observations, performance counters, and evidence volumes as the differential baseline.
- [ ] Establish canonical FeatureSpec and SettingSpec authorities that generate or validate identities, settings, locale, docs, targets, migrations, test obligations, and backport dispositions.
- [ ] Split the broad provider interface into composable fact, discovery, normalization, policy, quality, presentation, runtime, migration, diagnostic, and fixture protocols.
- [ ] Introduce typed policy fragments, field-specific conflict algebra, immutable decision traces, and orthogonal compatibility maturity, scope, and behavior claims.
- [ ] Route every MIR prototype mutation through governed normalization or technology transformation plans with exact operation IDs, before/after fingerprints, journals, and postconditions.
- [ ] Replace manual runtime routing with versioned runtime feature specifications, state schemas, lifecycle subscriptions, target requirements, and migrations.
- [ ] Split compilation_plan.lua, require explicit pure compiler inputs, introduce typed context keys, add validation-only mutation sentinels, and remove forbidden dependency cycles.
- [ ] Add RecipeFactV3, a bipartite process graph, deterministic process-role classification, and explicit net-flow proofs for complex chemistry, biology, recovery, recycling, catalyst, matter, and correlated-output families.
- [ ] Modularize the PowerShell control plane behind stable ABIs before extracting the typed cross-platform mirctl kernel and thin platform launchers.
- [ ] Replace nested suites with an atomic task DAG, reusable observations plus independent evaluations, generated and mutation-tested semantic impact, exact cache explanations, failure-directed reruns, and resource-aware scheduling.
- [ ] Replace copied release views with immutable per-release and release-transition records, a release state machine, generated documentation, and machine-readable changesets.
- [ ] Make 2.6.x an executable deterministic projection of immutable 3.3.x source plus the Factorio 2.0 profile and adapters; retain the target-first/source-second merge only as provenance.
- [ ] Move future raw archives, logs, saves, complete historical source trees, and large evidence bundles out of active Git while retaining compact identities and immutable asset receipts.
- [ ] Qualify ecosystems in evidence-driven order and promote only reviewed attachments, exact owners, bounded machine/lab families, and exact material families before specialized complex processes.

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

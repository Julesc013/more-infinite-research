# M.I.R. TODO

Updated: 2026-07-13

This is the executable release queue. `.mir/release-wave.yml` is the machine-readable status authority. Detailed architecture and acceptance criteria live in the linked governed records.

## Current Truth

- MIR 3.1.1 for Factorio 2.1 and MIR 2.3.5 for Factorio 2.0 are the published immutable baselines.
- MIR 3.1.2 is the untagged emergency technology-cycle hotfix under validation on `dev`.
- MIR 2.4.0 is unreleased and begins from the accepted 3.1.2 source only after the modern gate closes.
- Earlier local 3.1.0 and 2.4.0 tags, commits, archives, and validation packets are superseded candidate evidence, not publication authority.
- Work temporarily labeled 3.2.0 has been preserved as 3.1.0 implementation or honest pre-renumber characterization. Work temporarily labeled 2.5.0 is preserved but non-authoritative until it is re-derived as 2.4.0.
- MIR 3.2.0 does not open on `dev` until 3.1.2, 2.4.0, and the descending backport distributions are stable and their portable lessons return.

## 3.1.2 Automatic Compiler Hotfix

### Technology Cycle Repair

- [x] Reproduce the reported `space-science-pack -> ... -> astroponics -> space-science-pack` mutual path.
- [x] Prove Factorio rejects an unrepaired external cycle rather than merely suppressing MIR's assertion.
- [x] Add one topology-gated Muluna and Astroponics repair that removes only `astroponics -> space-science-pack`.
- [x] Keep the repair inactive without both mods or without the reverse prerequisite path.
- [x] Keep generated-node cycles, missing prerequisites, and disabled prerequisites fatal.
- [x] Replace recursive graph walking with a deterministic iterative walk and a 4,096-node regression.
- [x] Add exact local closure metadata for Astroponics, Muluna, and Secretas; the available Astroponics 1.7.3 archive fails earlier on its own removed Factorio helper and does not qualify as MIR load evidence.
- [ ] Bind the complete 91-scenario Factorio 2.1 matrix, exact archive, upgrade, and available ecosystem checks to the clean 3.1.2 candidate.

### Implemented

- [x] Pure GenerationPlan schema 3 boundary with evidence-bearing gates before prototype mutation.
- [x] All fixed streams and deferred family adoption route through whole-plan validation.
- [x] RecipeFactV2 resolves target-aware defaults and preserves variant, type, independent/shared probability, extra-count, freshness, quality, catalyst, productivity-exclusion, surface, and recycling evidence.
- [x] Shared phase-labelled input/output recipe, entity, unlock, effect-owner, lab, module, upgrade, subgroup, and surface indexes.
- [x] One effect metadata authority drives identity, units, scaling, target support, settings, and emission checks.
- [x] Positive TargetProfileV2 and declaration-owned setting requirements.
- [x] FamilyRule schema 2 with structural selectors, hard safety requirements, risk denials, ownership, science, prerequisites, targets, and claims.
- [x] CompatibilityPack schema 2 with operational applicability groups, aliases, exact selectors, family hints, science roles, owner claims, reviewed-risk boundaries, and precedence.
- [x] Non-overridable hard CompatibilityPack blockers, explicit family/stream authorization for exact recipes, and provenance-bound candidate seeding.
- [x] Structural attachment for modules, loaders, belts, drills, inserters, furnaces, assembling machines, labs, and solar/storage families.
- [x] Reviewed stable generic assembler and lab identities behind `safe-generate`; default remains `safe-attach`.
- [x] Stable generated-ID manifest and golden checks for 70 existing plus two reviewed family identities.
- [x] Complete recipe accounting categories with stable reasons and coverage fingerprints.
- [x] Shared-input/output, catalyst-return, recycling, probability, and external-owner safety vetoes.
- [x] Auditable scale counts and a real 1,000-recipe, 1,000-technology, 10,000-effect synthetic gate.
- [x] Dependency-ordered command graph and deterministic package construction.
- [x] Command-DAG orchestration, pre-emission base-continuation planning, duplicate semantic-effect rejection, and final plan/output owner parity.
- [x] CompilationPlan schema 2 global finalization with source/base/operation fingerprints and numeric, effect, prerequisite, science, generated-registry, and base-mutation output parity.
- [x] Runtime scenario schema 3 with exact-package reuse, scenario/group/tag/tier/impact selection, isolated parallel execution, structured assertions, and failure packets.
- [x] Exact-archive load characterization for AAI, BZ, Bob, Krastorio base, and K2SO at `loads` claim level only.

### Required Before Candidate Freeze

- [x] Finish campaign scenario schema 2 ownership: target, setup, roots, settings, expected plan, timeout, and claim level are validated data rather than duplicated PowerShell call arguments.
- [x] Add minimal-Factorio pure schema and algorithm tests for invalid FamilyRules, invalid CompatibilityPacks, equal-precedence conflicts, deterministic precedence, target/applicability filtering, stable IDs, stable sorting, and deterministic fingerprints.
- [x] Move competing-owner replacement, productivity-family adoption, weapon-speed, and max-level mutation bodies out of `policy/` into `pipeline/mutations/` or `emit/transactions/`; policy stays plan-only.
- [x] Replace remaining hybrid target denylists with positive feature, mod, effect, emitter, and shape declarations; every target now fails closed from allowlists.
- [x] Add deterministic plan/coverage snapshot export, plan and target-plan diff, review-required CompatibilityPack scaffolding, snapshot minimization, and static tool tests.
- [x] Consolidate effect, stream, descriptor, rule, pack, plan, fact, and scenario authorities into one governed table with code/manifest/doc schema drift checks.
- [x] Review and lock every automatic effect value and generated science/prerequisite choice for balance and reachability.
- [x] Keep beacon diagnostic-only and retain rail/support, ammunition, armor, battery, circuit, plate, and structural components under existing fixed streams; add no unproved broad rules in 3.1.0.
- [x] Keep complex chemistry, catalyst, recovery, voiding, transmutation, recycling, probabilistic output, and multi-output loops report-only until graph proof exists.
- [x] Define a distinct deferred RecipeVariantPlan contract for recycling-safe duplicate recipes without authorizing any 3.1.0 implementation.

### Final 3.1.2 Evidence

- [x] Reproduce the Space Age Galore multi-output collision with `vgal-coal-crushing` matched by carbon and sulfur streams.
- [x] Resolve cross-stream recipe effects to one deterministic owner while retaining unique effects and the final malformed-duplicate assertion.
- [x] Prove deterministic insertion order, partial-loss retention, adoption precedence, same-stream rejection, and exactly one Galore-shaped owner.
- [ ] Rebuild and bind the complete 91-scenario runtime, exact-upgrade, exact-dist, ecosystem, and interactive evidence to 3.1.2.

- [x] Complete RC6 correctness matrix on Factorio 2.1.9 after effective-default, product-shape, CompatibilityPack, plan-proof, base-planning, and output-parity changes (`86/86`).
- [x] Reconcile the two `main`-only changes before promotion: preserve the MIR 2.x requirement wording and keep the host-specific history exporter deleted; the final deterministic package SHA-256 is `269C27DC...B1A7DB`.
- [x] Mark RC5 evidence superseded and reopen candidate construction; RC6 automated runtime success is development evidence until committed candidate identities and interactive review are rebound.

- [x] Clean static validation after fixed-point release-harness evidence binding at validation source `2490d2d`, package evidence source `4cdb859`, and package source anchor `81e73ea`.
- [x] Complete Factorio 2.1.9 declared runtime matrix with no skipped required group at validation source `2490d2d` (`86/86`).
- [x] Exact 3.0.5-to-3.1.0 save upgrade with non-default settings, research levels, storage, and scripted effects retained against RC4 archive `BD89A34D...DDDA3`.
- [x] Exact 3.1.0 development archive base and Space Age loads from an isolated normal mods directory; rerun if package-visible source changes.
- [x] Final-version performance evidence with recipe, technology, effect, edge, candidate, and scan counts; rerun if package-visible source changes.
- [x] Rerun every locally complete exact-archive campaign for AAI, BZ, Bob, Krastorio/K2SO, and the representative 46-mod planet cluster against the hardened archive (`9/9`, `loads` claims only).
- [x] Characterize the earlier final-version archive across all currently complete local closures: AAI, BZ, Bob, Krastorio base, and K2SO (`8/8`, zero dependency failures).
- [x] Rerun the available exact-archive `loads` scenarios against source `3699fec` (`9/9`, zero dependency failures), including a complete 46-mod planet cluster.
- [ ] Acquire complete Angel, Space Exploration, and Pyanodon dependency closures, then run their independent exact-archive campaigns.
- [x] Bind the remaining closure blockers to exact missing archive identities and reject zero-root process success as compatibility evidence.
- [x] Preserve `loads`, `observed`, `cooperates`, partial-family, and full-family claim boundaries; inventory never counts as proof.
- [ ] Interactive settings, locale, icon, technology-tree, save-load, and balance review on the exact candidate.
- [x] Preserve the superseded RC2-RC5 archives, release notes, migration guide, validation summaries, upgrade proof, campaign lock/evidence, and pending identity-bound GUI packet as historical evidence.
- [x] Rebind user-facing settings source `b9293df`, archive `25B166D5...637DAB3`, the `89/89` validation summary, exact upgrade proof, `9/9` ecosystem campaign, and a fresh pending interactive packet.
- [ ] Complete and bind the GUI review without rebuilding the archive.
- [x] Revalidate the unchanged planet-safe package after campaign evidence is hardened so unresolved roots cannot report a passing claim row.
- [x] Rebuild and requalify after the representative planet cluster exposed a generated base extension anchored to a disabled prerequisite chain.
- [x] Fast-forward accepted `dev` to `main` and synchronize local/origin `dev` and `main` at the same RC7 evidence commit.
- [ ] Complete the 3.1.2 RC evidence and synchronize `dev` and `main` without tagging or publishing.

## 2.4.0 Factorio 2.0 Companion

- [ ] Start only from the accepted 3.1.2 source; preserve the current experimental 2.0 work as reference, not authority.
- [ ] Apply only Factorio 2.0 metadata, dependency floors, target effect cuts, schema adapters, target fixture shapes, and target assets.
- [ ] Share fact, rule, pack, plan, ID, coverage, test, package, and evidence schemas with 3.1.2.
- [ ] Preserve 2.3.5 technology IDs, settings, runtime namespaces, and save behavior.
- [ ] Run clean static, complete Factorio 2.0.77, exact-package base/Space Age, 2.3.5 upgrade, performance, campaign, and interactive gates.
- [ ] Return portable target dispatch, fixture, harness, and fixed-point lessons to `dev` without returning 2.0 metadata or feature cuts.
- [ ] Publish exact 2.4.0 bytes only after independent acceptance.

## Descending Backport Ladder

### 1.9.4 - Factorio 1.1

- [ ] Keep the qualified candidate frozen until the new portable contracts are selected deliberately.
- [ ] Port deterministic IDs, schema validation, plan/report records, positive target profiles, native ownership, prerequisite safety, and reusable validation only.
- [ ] Do not simulate modern recipe productivity.
- [ ] Requalify on Factorio 1.1.110 if any package-visible source changes.

### 1.8.2 - Factorio 1.0

- [ ] Keep 1.8.2 as the next version; do not skip to 1.8.3 without a real release event.
- [ ] Repair current staged runtime proof on the matching 1.0 binary.
- [ ] Apply only portable contracts supported by the target API.

### 1.7.1 - Factorio 0.17

- [ ] Refresh from the proven 1.7.0 native-infinite baseline using matching binary evidence.
- [ ] Preserve target-era science, assets, runtime backend, and exact effect allowlist.

### 1.6.0 - Factorio 0.16

- [ ] Create a current plan; keep obsolete archived version slots historical.
- [ ] Implement old-science role adapter, target recipe schema, exact effect allowlist, native infinite proof, and target assets.
- [ ] Prove no modern dependency, DLC, metadata, or API leakage on Factorio 0.16.51.

### 1.5.0 - Factorio 0.15

- [ ] Create a current plan and independent native-infinite or finite fallback proof on Factorio 0.15.40.
- [ ] Apply old-science, recipe-shape, asset, and dependency adapters without modern simulation.

### 1.4.0 - Factorio 0.14

- [ ] Establish matching base-file and binary truth, then choose native infinite or finite ladder from evidence.
- [ ] Materialize target plan, package hygiene, migration limits, and exact load proof.

### 1.3.0 - Factorio 0.13

- [ ] Establish target-era prototype, science, locale, asset, and package schemas from the matching binary.
- [ ] Build only the proven finite/native subset and record explicit omissions.

## Fixed-Point Return And 3.2.0 Gate

- [ ] After every target, classify portable lessons versus target-local cuts.
- [ ] Return portable correctness, determinism, schema, tooling, and diagnostics improvements to `dev` in isolated commits.
- [ ] Rerun 3.1.0/modern characterization after the final return; no behavioral drift without explicit release action.
- [ ] Open MIR 3.2.0 on `dev` only when 3.1.0 and 2.4.0 are released, the listed backport distributions are stable, and the return sweep reaches a fixed point.

## Recurring Gate

- [ ] `git status --short --branch`
- [ ] `git diff --check`
- [ ] `./scripts/Invoke-MIRValidation.ps1 -StaticOnly`
- [ ] Run the matching Factorio binary matrix.
- [ ] Run the matching release-targeted profile against its pinned local mod library.
- [ ] Load the exact candidate archive in every supported official-mod configuration.
- [ ] Run the prior-release save upgrade.
- [ ] Verify candidate freshness from a clean tree.
- [ ] Complete interactive save/settings review.
- [ ] Publish the exact validated bytes without rebuilding.

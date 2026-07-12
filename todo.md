# M.I.R. TODO

Updated: 2026-07-12

This is the executable release queue. `.mir/release-wave.yml` is the machine-readable status authority. Detailed architecture and acceptance criteria live in the linked governed records.

## Current Truth

- MIR 3.0.5 for Factorio 2.1 and MIR 2.3.5 for Factorio 2.0 are the published immutable baselines.
- MIR 3.1.0 is unreleased and under active automatic-compiler refactor on `dev`.
- MIR 2.4.0 is unreleased and begins from the accepted 3.1.0 source only after the modern gate closes.
- Earlier local 3.1.0 and 2.4.0 tags, commits, archives, and validation packets are superseded candidate evidence, not publication authority.
- Work temporarily labeled 3.2.0 has been preserved as 3.1.0 implementation or honest pre-renumber characterization. Work temporarily labeled 2.5.0 is preserved but non-authoritative until it is re-derived as 2.4.0.
- MIR 3.2.0 does not open on `dev` until 3.1.0, 2.4.0, and the descending backport distributions are stable and their portable lessons return.

## 3.1.0 Automatic Compiler

### Implemented

- [x] Pure GenerationPlan schema 2 boundary before prototype mutation.
- [x] All fixed streams and deferred family adoption route through whole-plan validation.
- [x] RecipeFactV2 preserves variant, type, probability, catalyst, productivity-exclusion, surface, and recycling evidence.
- [x] Shared recipe, entity, unlock, effect-owner, lab, module, upgrade, subgroup, and surface indexes.
- [x] One effect metadata authority drives identity, units, scaling, target support, settings, and emission checks.
- [x] Positive TargetProfileV2 and declaration-owned setting requirements.
- [x] FamilyRule schema 2 with structural selectors, hard safety requirements, risk denials, ownership, science, prerequisites, targets, and claims.
- [x] CompatibilityPack schema 2 with applicability, refinements, targets, evidence, claims, and reviewed-risk boundaries.
- [x] Structural attachment for modules, loaders, belts, drills, inserters, furnaces, assembling machines, labs, and solar/storage families.
- [x] Reviewed stable generic assembler and lab identities behind `safe-generate`; default remains `safe-attach`.
- [x] Stable generated-ID manifest and golden checks for 70 existing plus two reviewed family identities.
- [x] Complete recipe accounting categories with stable reasons and coverage fingerprints.
- [x] Shared-input/output, catalyst-return, recycling, probability, and external-owner safety vetoes.
- [x] Auditable scale counts and a real 1,000-recipe, 1,000-technology, 10,000-effect synthetic gate.
- [x] Dependency-ordered command graph and deterministic package construction.
- [x] Exact-archive load characterization for AAI, BZ, Bob, Krastorio base, and K2SO at `loads` claim level only.

### Required Before Candidate Freeze

- [ ] Finish scenario schema 2 ownership: setup, roots, settings, expected plan, timeout, and claim level must be data, not duplicated PowerShell call arguments.
- [ ] Add pure schema and algorithm tests for invalid FamilyRules, invalid CompatibilityPacks, conflict merging, precedence, target filtering, stable IDs, and deterministic fingerprints.
- [ ] Move remaining prototype mutation bodies out of `policy/` into `pipeline/mutations/` or `emit/transactions/`; policy stays pure.
- [ ] Replace remaining hybrid target denylists with positive feature and shape declarations where target evidence exists.
- [ ] Add plan export/diff, coverage export, compatibility-pack scaffold, snapshot minimizer, and target-plan diff tooling.
- [ ] Consolidate the final effect/stream/rule/pack documentation tables and add schema drift checks.
- [ ] Review every automatic effect value and generated science/prerequisite choice for balance and reachability.
- [ ] Decide whether beacon, rail/support, ammunition, armor, battery, circuit, plate, structural-component, or fluid-process families remain report-only or receive fixture-backed rules.
- [ ] Keep complex chemistry, catalyst, recovery, voiding, transmutation, recycling, and multi-output loops report-only until graph proof exists.
- [ ] Add a distinct RecipeVariantPlan design for recycling-safe duplicate recipes only after the core candidate is accepted; do not fold it into this release unless separately authorized.

### Final 3.1.0 Evidence

- [x] Clean static validation after version/governance reconciliation at source `1b91c40`.
- [x] Complete Factorio 2.1.9 declared runtime matrix with no skipped required group at source `1b91c40` (`85/85`).
- [ ] Exact 3.0.5-to-final-3.1.0 save upgrade with non-default settings, research levels, storage, and scripted effects retained.
- [x] Exact 3.1.0 development archive base and Space Age loads from an isolated normal mods directory; rerun if package-visible source changes.
- [x] Final-version performance evidence with recipe, technology, effect, edge, candidate, and scan counts; rerun if package-visible source changes.
- [ ] Independent exact-archive campaigns for AAI, BZ, Bob, Angel, Krastorio/K2SO, Space Exploration, Pyanodon, and representative planet mods where complete dependency closures are available.
- [x] Final-version exact-archive `loads` campaigns for all currently complete local closures: AAI, BZ, Bob, Krastorio base, and K2SO (`8/8`, zero dependency failures).
- [ ] Acquire complete Angel, Space Exploration, Pyanodon, and representative planet dependency closures, then run their independent exact-archive campaigns.
- [ ] Preserve `loads`, `observed`, `cooperates`, partial-family, and full-family claim boundaries; inventory never counts as proof.
- [ ] Interactive settings, locale, icon, technology-tree, save-load, and balance review on the exact candidate.
- [ ] Candidate freshness, deterministic package, release notes, migration guide, validation summary, and final archive hashes from one clean commit.
- [ ] Push accepted `dev` to `main`, create the real 3.1.0 tag, publish exact validated bytes, then mark immutable.

## 2.4.0 Factorio 2.0 Companion

- [ ] Start only from the accepted 3.1.0 source; preserve the current experimental 2.0 work as reference, not authority.
- [ ] Apply only Factorio 2.0 metadata, dependency floors, target effect cuts, schema adapters, target fixture shapes, and target assets.
- [ ] Share fact, rule, pack, plan, ID, coverage, test, package, and evidence schemas with 3.1.0.
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

---
title: "MIR 4 Post-4.0 Roadmap"
status: current
applies_to: "MIR 4.0.1+"
audience: maintainer
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-09-05
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-post-4.0-roadmap
---

# MIR 4.x operating programme

MIR 4.0.0 proved that the project can produce a multi-target, proof-governed product line. MIR 4.x now has two simultaneous duties: keep the released 4.0 line repairable and make future development physically coherent. The programme therefore runs a stable patch lane and one development lane under shared findings, shared semantic intent, independently qualified target packages, and immutable published bytes.

The objective is not another platform layer. It is one semantic source, one obvious repository structure, one public command surface, one authority per mutable fact, one generated release narrative, independently generated target packages, and detailed evidence that never clutters or enters the player package.

The machine-readable programme is `spec/programmes/mir4-4x-operating-programme-v1.json`. The self-contained package promise is `spec/distribution/mir4-deployment-contract-v1.json`; patch semantics are in `spec/releases/mir4-patch-policy-v1.json`; proof applicability is in `spec/assurance/mir4-proof-applicability-v1.json`.

## Permanent product invariants

- A player downloads one self-contained MIR ZIP for the selected Factorio target. Official MIR features and integrations for that target are inside it and are inert when the corresponding external mod is absent.
- Optional extensions may add behavior but cannot be required to recover a capability advertised as part of MIR.
- F210 and F200 are primary maintained targets. F110 and F100 are conditional targets that qualify independently and may publish later without delaying an otherwise complete source release. Older targets remain experimental or museum work until exact engine, predecessor, rights, package, and support custody exist.
- Until the first official Factorio 2.1 stable release, F210 selects the latest official experimental build installed by Steam. The channel is moving, but every proof binds one exact version and executable hash. Each observed engine or API change creates a required feature, implementation, compatibility, fixture, runtime, performance, documentation, and stable-transition review task set before its evidence can be treated as current.
- Each target receives its own numeric distribution version, package, engine proof, qualification, seal, publication receipt, and public readback. Evidence from one target never substitutes for another.
- Compatibility policy supplies facts, claims, profiles, and proof requirements; it never mutates prototypes. Only admitted emission code creates or changes generated technology prototypes.
- Published versions, tags, and package bytes are immutable. The unsigned `v4.0.0` tag and its historical annotation are preserved rather than rewritten.
- Repository, governance, documentation, fixtures, tests, SDK material, build records, and assurance evidence remain outside player ZIPs.

## Stable maintenance and next-release development

`release/4.0` is the maintained 4.0.x line rooted at the exact peeled `v4.0.0` commit. It accepts only reproduced player defects, security corrections, save or migration repairs, exact-target compatibility corrections, and release-copy or installation corrections. It does not accept repository redesign, feature work, compiler decomposition, or speculative cleanup.

`main` is the latest-stable MIR 4.x line. Bounded patches, hotfixes, repository-governance maintenance, and exact qualified release promotions target `main`. It is not the integration queue for the next minor or major release.

`dev` is the next-minor or next-major integration line. Feature, architecture, refactor, preview, target, and release-engine work starts from `dev`. Every stable correction on `main` receives an explicit semantic forward-port disposition on `dev`; every public minor or major advances `main` only by exact qualified promotion from `dev`.

A finding that originates on `release/4.0` is fixed with the smallest valid 4.0 change and forward-ported semantically through `main` to `dev`. A finding that originates on stable `main` is forward-ported to `dev` and backported to `release/4.0` only when it reproduces against the exact 4.0 base. A finding discovered on `dev` is corrected there first and reaches `main` only through a qualified release promotion unless the defect also independently reproduces on stable `main`. Every direction requires one shared finding ID, target dispositions, semantic-equivalence evidence, upgrade evidence, and an explicit package delta. Merging an older lane wholesale into a newer lane is forbidden.

For source patch `4.0.1`, distribution versions are `4.0.21001`, `4.0.20001`, `4.0.11001`, and `4.0.10001`. The established codec remains `target code × 100 + source patch`; no ad hoc target version namespace is introduced.

## Dependency-ordered work

The governance and characterization foundation is complete, so MIR 4.1 now owns the physical and executable fixed point as well. Completion means zero ambiguity, duplicate writers, uncontrolled bridges, unexplained package differences, stale current authorities, or release-critical transitional dependencies. It does not require deletion of bounded, read-only, package-excluded history.

| Work package | Outcome | State after this change |
| --- | --- | --- |
| M40-00 | Preserve exact 4.0.0 refs, assets, remote controls, and offline restore closure | Complete |
| M40-01 | Operate the protected `release/4.0` maintenance lane | Active; unpublished synthetic rehearsal passed |
| M41-00 | Adopt operating, deployment, patch, and proof-applicability contracts | Complete |
| M41-01 | Repair pull-request proof selection for event base, trust class, and synthetic merge topology | Complete |
| M41-02 | Converge GitHub rules, community health, security automation, and one stable required check | Complete |
| M41-03 | Introduce change fragments and generate every release narrative | Complete |
| M41-04 | Prove protected stable-to-`dev` exact-tree convergence during branch transition | Complete |
| M41-06 | Establish `main` as latest stable and `dev` as the next-minor or next-major integration line | Complete |
| M41-05 | Route documentation by reader need, then separate repository and package landing pages | Complete: M41-05A routing and M41-05B package-documentation cutover accepted |
| M42-00 | Establish one package source, target overlays, one materializer, and four independently generated targets inside the 4.1 completion boundary | Complete: F1 through F2E accepted; `src/mod`, `targets`, and `TargetMaterializer` are current package authority |
| M42-01 | Converge PowerShell, executable tests, proof catalogues, workflows, and release orchestration behind one supported public surface | Complete |
| M42-02 | Perform only reviewable behavior-preserving Lua and PowerShell decomposition needed for the 4.1 maintainability fixed point | Complete: six Lua and eleven PowerShell responsibility splits accepted; bridge retirement and private four-target qualification remain separate MIR 4.1 gates |
| M41-07 | Retire every current-product authority bridge and bound retained historical readers | Complete: zero current-product authority bridges; retained compatibility paths are read-only, owned, tested, package-excluded, and expiry-bounded |
| M41-08 | Freeze, build, qualify, seal, and promote the private four-target MIR 4.1 candidate | Active: bridge closure accepted; private four-target release readiness follows |

Only one authority migration, one feature train, and one stable patch may be in flight at once. A stable player defect can pre-empt the feature train, but it does not broaden patch scope. No implementation decomposition starts before M42-00 proves source/package characterization, deterministic target builds, upgrade continuity, and rollback. A split that cannot be reviewed and proved safely remains unchanged with an explicit disposition.

The accepted F2D chain is complete for F210, F200, F110, and F100, including the independent four-target aggregate. F2E then bound stable target identity separately from version projection, promoted `src/mod` and `targets` as canonical editable source, routed ordinary and target-product construction through `TargetMaterializer`, and fenced the bootstrap writer as historical compatibility. Four fresh deterministic reconstructions matched the accepted 4.0 content roots and entry sets. M41-07 completed the physical retirement: the repository root is not an editable Factorio package, and historical root-package bytes can be read only through explicit immutable-commit compatibility paths.

M41-05B replaced the root README with a concise package-excluded repository landing page and made target player documentation a generated package projection. Repository and player narratives now have separate owned audiences and generated views.

## Preserved 4.0.0 baseline

The post-release programme began from annotated tag object `65b6d49a08546085e905f487e4b821578de63a68`, peeled commit `5ca449820bdfa5595ca03686f32c74904c46daf3`, and tree `83527c89f58e2d49edbc06dbae8fe747081ebc68`. The pre-release `dev` commit `9a8477aa83300646d41922efd39adb728c6a28e2` has that same tree. `release/4.0` was created at the peeled release commit and protected by GitHub ruleset `21859574`.

The offline pre-refactor Git bundle was restored successfully and has SHA-256 `F63A120B800C11D8D6E59652B3620D6B28FAA9C123141C7B21D9FE3AE91832A0`. GitHub release `379184899` remains published as `MIR 4.0.0`; its unsigned tag, historical annotation, mutable-release state, blank asset labels, and exact bytes are observations to preserve rather than history to rewrite.

| Asset | Bytes | SHA-256 |
| --- | ---: | --- |
| `more-infinite-research_4.0.21000.zip` | 1,069,552 | `38541A7ED0A4181811A1E94231FF58A1268F91E7B89C7CA3D9D5F682242094B1` |
| `more-infinite-research_4.0.20000.zip` | 1,067,014 | `5C0E299D78C4EE545958448DAE48D87BE5FE1B959875D4CB93A264D95D3DB0AE` |
| `more-infinite-research_4.0.11000.zip` | 399,073 | `BE63F76255068BAC1BA891B9C9331E4EA943538A37808DFF546E5B1A3ECEB62D` |
| `more-infinite-research_4.0.10000.zip` | 399,073 | `EA495B37C0B91F0728226290CDAEFDF4BBD3C1DBA7D0997AAF5E5107FE79AD3F` |
| `mir4-api-sdk-v1-preview.zip` | 69,800 | `78A9469C19CA2AFCDD6F53C1171DD7F8E3734B4AB59546A39523E1CE3F509CD3` |
| `mir4-inspector-v1-preview.zip` | 50,706 | `66F3807B53E5088F4FE15427B91C35ED9205B2AFFAD65B498A4AA532DF9BFBC2` |
| `mir4-mep-v1-preview.zip` | 94,105 | `D221B813B39030A9B3FA14800EE8C59846D3D0CF5BF90A29D8DD70CE5CC0619E` |
| `mir4-reference-extension-v1-preview.zip` | 20,577 | `A0ABA772A6115882E32838B2189F504250B8E354D57A90C5A8AA5E77204D5183` |
| `SHA256SUMS.txt` | 798 | `054536B8CE1C05E47C1166294EC9427EC70A3B612F1DA0AD599C5E6EC3B20E7D` |

The Mod Portal API exposed F210, F200, and F110 with SHA-1 values equal to the downloaded GitHub bytes. F100 was not present in the observed portal release list. No 4.0.1 source version is allocated by this record.

The dated MIR 3 `.9` Mod Portal visibility observation remains immutable. Its stored self-hash used the earlier date conversion that normalized one `.140Z` timestamp to `.14Z`; `.mir/evidence/terminal-publication/2026-08-16/mod-portal/MIR3-Dot9-ModPortal-Visibility-Canonicalization-ReconciliationV1.json` binds the original bytes, legacy digest, and lexical RFC 3339 digest. The reconciliation grants no current portal claim, history rewrite, build, tag, upload, allocation, or publication authority.

## Stable repair procedure

The first operational rehearsal is recorded in `releases/rehearsals/MIR4-M40-01-Patch-Lane-Rehearsal-2026-08-31.json`. It created and removed a disposable local branch from the exact `release/4.0` base, selected only F210 as affected, recorded F200/F110/F100 as unchanged without manufacturing packages, produced a deterministic qualification and semantic forward-port plan, rejected publication-authority tampering, preserved all remote refs, and left the player package source fingerprint unchanged. This proof keeps M40-01 operational; it does not allocate 4.0.1 or authorize a real correction.

Triage a defect once under one finding ID. Record reproduction, severity, affected targets, save or migration impact, compatibility scope, package-visible paths, and every lane disposition. For a 4.0-origin defect, branch from `release/4.0`, make the smallest correction, prove each exact affected package, and forward-port the semantic intent and regression fixture through `main` to `dev`. For a current-stable defect, correct `main`, forward-port it to `dev`, and backport it to 4.0 only after exact-base reproduction. For a next-release defect, correct `dev`; do not manufacture a stable change unless the same finding independently reproduces there.

Never merge either lane wholesale into the other. A bounded cherry-pick is acceptable only when it carries no irrelevant history; otherwise implement the same intent separately and bind both changes with semantic-equivalence, upgrade, target-disposition, and package-delta evidence. F210 and F200 remain primary independently qualified targets. F110 and F100 qualify independently and may publish later as supplemental target releases.

## Outcome trains

Version numbers below are candidate labels assigned only at source freeze. Outcomes may be combined, split, skipped, or renumbered.

| Candidate | Required outcome |
| --- | --- |
| 4.0.x | Verified stable defects only; no release exists merely to carry repository work |
| 4.1.0 | Truthful repository; one package source; four target products; one CLI; one release engine; one executable test authority; generated repository and package documentation; bounded maintainable implementation; zero mutable dual authority |
| 4.2.0 | Integration kernel and rolling built-in ecosystem admissions across ownership, progression, productivity, finalizers, recovery, runtime-mediated channels, and exact advanced-process certificates; public extension contracts still graduate individually |
| 4.3.0 | Industrialized semantic-impact selection, evidence reuse and revocation, partial-run recovery, nondeterminism handling, measured release lanes, offline operation, EOL automation, and recurring architecture audits |
| 4.4.0+ | Unallocated until evidence supports a coherent external outcome |

The next major begins only when a change cannot be delivered honestly under MIR 4 settings, technology identity, save migration, API, and distribution promises.

## Release operation

Public source releases use plain names such as `MIR 4.1.0`, `MIR 4.1.0 Beta 1`, and `MIR 4.1.1`. Internal programme themes do not appear in release titles. Future source tags are annotated and signed; target tags use `dist/fNNN/v<distribution-version>`.

A source release is drafted only after source freeze. Every ready target package is attached to the primary source-family release. A target that completes later may use a supplemental target release, preserving source-release immutability without lowering that target's proof bar. The default stable asset set is the affected player ZIPs, one Developer Kit when developer surfaces changed, `SHA256SUMS.txt`, one release manifest, and an optional detailed metadata archive.

Release bodies contain one material-outcome sentence, a small download table, three to eight primary changes, upgrade and compatibility guidance, material known issues, and links to detailed records. They contain no raw logs, local paths, candidate ceremony narrative, or full evidence dump.

## Decision gates

Every work package must name one exact base, one bounded writer, one reversible change, the selected proof closure, any required independent review, and post-merge readback. A component graduates per contract, never because a whole preview bundle has existed for long enough. A proof is valid only for its declared event, trust class, ref topology, credential class, environment class, and simulation or realization mode.

Progress is measured by fixed points closed, ambiguity removed, stable lead time, target build time, flaky-test rate, escaped defects, proof reuse, and the time required to restore an exact release—not by the number of version labels consumed.

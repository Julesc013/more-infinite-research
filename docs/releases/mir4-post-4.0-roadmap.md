---
title: "MIR 4 Post-4.0 Roadmap"
status: draft
applies_to: "MIR 4.0.1+"
audience: maintainer
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-30
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-post-4.0-roadmap
---

# MIR 4 post-4.0 roadmap

This roadmap begins after the immutable MIR 4.0.0 release event. It does not alter the accepted 4.0.0 packages, qualify an unaccepted target, graduate a preview subsystem, move the `legacy` branch, or authorize publication by itself. Each release still requires exact target-local evidence and the normal release gates.

## Release-line rules

- `dev` remains the integration branch for MIR 4 work.
- `main` receives only qualified release promotions.
- `legacy` remains the previous-major MIR 3 alias throughout MIR 4 unless a separate, reviewed historical-succession authority moves it after a future major release.
- Patch releases preserve public settings, technology identities, migration continuity, and package-source parity except for a narrowly documented correctness or compatibility fix.
- Minor releases may add capabilities, but preview, shadow, and experimental components graduate only through subject-specific acceptance evidence.
- Every supported Factorio target keeps its own distribution version, engine lock, package identity, qualification evidence, and publication receipt.

## MIR 4.0.1 — release feedback and correctness

Purpose: close verified defects or documentation gaps found during the 4.0.0 publication and early adoption window without starting an architecture cutover.

Planned scope:

- reconcile GitHub and Mod Portal release copy, FAQ answers, installation guidance, and compatibility wording against public readback;
- fix reproducible player-facing defects in the admitted emitter while preserving one-emitter package-source parity;
- strengthen diagnostics for invalid settings, missing optional technologies, migration problems, and target-specific omissions;
- capture upgrade evidence from the exact 4.0.0 target packages to every 4.0.1 target candidate;
- retain F210 and F200 as mandatory targets and evaluate F110 and F100 independently under their conditional release policy;
- keep developer preview archives separate from player ZIPs and keep all repository, proof, fixture, and tooling content package-excluded.

Exit criteria:

- every included change has a named issue, reproduction, affected-target analysis, and exact verification evidence;
- deterministic rebuilds reproduce every accepted target ZIP;
- direct upgrade, reload, configuration, compatibility, and performance checks pass on each released target;
- signing, sealing, offline restore, publication, and public readback close under the same production controls as 4.0.0.

## MIR 4.1.0 — first governed feature train

Purpose: deliver the first post-bootstrap feature release while converting only proven platform work from preview or shadow status into supported production behavior.

Candidate scope, subject to separate acceptance decisions:

- player-facing research configuration improvements that preserve stable technology identity and explicit target capabilities;
- selective graduation of target-compiler or semantic-compiler responsibilities after parity, migration, rollback, and package-boundary proof;
- a supported extension surface derived from the experimental API and module SDK, with a versioned compatibility contract and negative tests;
- improved inspector and compatibility diagnostics backed by exact fixture and engine evidence;
- ProcessIR-based analysis or synthesis only where it reproduces admitted emitter output and does not create a second uncontrolled production emitter;
- clearer target capability reporting for omitted, unsupported, and compatibility-provided research families.

Non-goals:

- blanket graduation of the MIR 4 platform preview;
- prototype mutation from compatibility policy;
- merging preview assets into player packages;
- claiming pack-wide compatibility from narrow evidence;
- changing historical branch aliases as a side effect of a minor release.

Exit criteria:

- each graduated subject has an authority transition naming its old and new owner, proof root, rollback route, and migration contract;
- public API and data-format changes have versioned schemas, examples, conformance tests, and compatibility policy;
- target-local packages remain deterministic, package-safe, and independently qualified;
- upgrades from the latest 4.0.x release pass on every published target.

## MIR 4.1.x — stabilization lane

Patch releases after 4.1.0 prioritize regressions, migration repair, compatibility evidence, documentation, and performance. New platform graduation waits for a minor release unless an urgent security or data-loss repair requires the emergency lane.

## MIR 4.2.0 and later — evidence-led expansion

Later minor trains may expand supported extension capabilities, inspection, synthesis, compatibility automation, or historical target tooling. A train is admitted only when its scope has an owner, target matrix, migration story, rollback plan, measurable acceptance criteria, and an evidence budget that can be completed before freeze.

Potential trains are ordered by proof readiness rather than implementation age:

1. graduate the smallest stable extension contract that external modules can test without receiving prototype-mutation or publication authority;
2. consolidate target and semantic compilation behind one production owner after exact fixed-point parity;
3. expand compatibility certification and inspection with subject-level claims;
4. improve offline assurance, reproducible release capsules, and public verification tooling;
5. consider additional historical targets only when exact engines, predecessor packages, and sustainable support custody exist.

## Next-major boundary

MIR 5 planning begins only when a change cannot be delivered honestly under MIR 4 compatibility and migration promises. The `legacy` alias may move from MIR 3 to the final supported MIR 4 line only through a dedicated succession event with public readback, preserved MIR 3 tags, and an explicit rollback route.

## Planning intake

Every proposed roadmap item should record:

- player or developer problem and expected outcome;
- affected targets and package-visible surface;
- owning module and authority transition, if any;
- compatibility, migration, rollback, and security impact;
- required fixtures, exact engines, tests, and human review;
- release-train recommendation and reasons it cannot fit a smaller train.

---
title: "MIR 3 Terminal .9 Programme"
status: current
applies_to: "3.2.9, 2.5.9, 1.9.9, 1.8.9, 1.7.9, 1.6.9, 1.5.9, 1.4.9, 1.3.9"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-08
supersedes: [docs/releases/3.2.5-to-2.6-convergence-programme.md, docs/releases/ultimate-convergence-audit-action-register.md, docs/architecture/3.3-2.6-convergence-platform-roadmap.md]
superseded_by: []
---

# MIR 3 Terminal `.9` Programme

This is the single planning authority for the final MIR 3 stabilization wave. It joins the current Factorio 2.1 line, the maintained Factorio 2.0 line, and every qualified historical target into one correction programme without turning the target ladder into a waterfall.

The programme is active as planning authority only. No `.9` candidate has been assigned, no `.9` source has been frozen, and no `.9` package has been built. MIR 4 implementation is not admitted by this record.

## Decision

- The published `.5` packages remain immutable.
- MIR `3.2.9`, `2.5.9`, `1.9.9`, `1.8.9`, `1.7.9`, `1.6.9`, `1.5.9`, `1.4.9`, and `1.3.9` are the only planned MIR 3 package destinations.
- Releases `.6`, `.7`, and `.8` are prohibited on these lines.
- Every product, package, migration, compatibility, locale, documentation, performance, and assurance correction discovered after `.5` is triaged into the corresponding `.9` release or explicitly deferred to MIR 4.
- MIR `3.3` and `2.6` are no longer active release trains. Their still-useful architecture ideas become MIR 4 inputs after the terminal `.9` wave.
- Publication exceptions used for `.5` do not lower the normal qualification policy for `.9`.

## Frozen starting point

| `.9` release | Factorio target | Immutable predecessor | Reserved candidate floor | Promotion shape | Current public state |
| --- | --- | --- | --- | --- | --- |
| `3.2.9` | `2.1` | `3.2.5` / C32 | `C33` | `dev` to fast-forward `main` | `3.2.5` publicly verified; protected debt retained |
| `2.5.9` | `2.0` | `2.5.5` / `2.5-P12` | `2.5-P13` | deterministic projection to fast-forward `legacy` | `2.5.5` publicly verified; protected debt retained |
| `1.9.9` | `1.1` | `1.9.5` | `1.9-P1` | deterministic two-parent tag-only integration | publicly verified |
| `1.8.9` | `1.0` only | `1.8.5` | `1.8-P1` | deterministic two-parent tag-only integration | publicly verified |
| `1.7.9` | `0.17` | `1.7.5` | `1.7-P1` | deterministic two-parent tag-only integration | publicly verified |
| `1.6.9` | `0.16` | `1.6.5` | `1.6-P1` | deterministic two-parent tag-only integration | publicly verified |
| `1.5.9` | `0.15` | `1.5.5` | `1.5-P1` | deterministic two-parent tag-only integration | publicly verified |
| `1.4.9` | `0.14` | `1.4.5` | `1.4-P1` | deterministic two-parent tag-only integration | publicly verified |
| `1.3.9` | `0.13` | `1.3.5` | `1.3-P1` | deterministic two-parent tag-only integration | publicly verified |

Factorio `0.18` support is not claimed for `1.8.5` or `1.8.9`. The `1.8.x` maintained line targets Factorio `1.0` only.

## One intake, nine dispositions

Every finding enters one terminal change set. Each finding receives exactly one canonical disposition before implementation:

| Disposition | Meaning |
| --- | --- |
| `portable` | Implement once on `dev`, then project without semantic change to every applicable target. |
| `portable-with-adapter` | Keep one canonical intent and use a bounded, named target adapter. |
| `target-local` | Correct only the affected historical target and prove that it does not alter other lines. |
| `package-excluded-assurance` | Correct release tooling, evidence, documentation, or CI without changing a frozen `.5` package. |
| `mir4-deferred` | Preserve the requirement for MIR 4 because it is a feature or platform redesign rather than a terminal stabilization correction. |
| `rejected` | Record why the proposal is unsafe, unsupported, redundant, or outside the terminal programme. |

Lower targets never inherit code from the next-newer lower target merely because it was processed first. Every projection starts from its immutable `.5` predecessor plus the exact portable `.9` source and target-local adapters.

## Workstreams

### T9-A: close retained `.5` assurance debt

Record post-publication protected qualification for `3.2.5` and `2.5.5` when it can be completed reliably. Reconcile normal seals and promotion admission without inventing a protected pass or mutating either public tag. Correct GitHub transport resilience, downstream `always()` guards, and the Stage B public-asset audit path. These are package-excluded obligations and do not authorize `.5` rebuilds.

### T9-B: freeze the terminal finding inventory

Collect every open product, package, migration, compatibility, locale, documentation, performance, and assurance finding. Bind each item to affected target lines, a reproducible proposition, migration impact, package visibility, and one of the dispositions above. Documentation-only ideas that alter the packaged README are still package-visible for `.9` planning.

### T9-C: implement and qualify `3.2.9`

Implement only admitted defect corrections and stabilization work on `dev`. Preserve stable technology, setting, locale, profile, migration, and runtime-state identities unless a named defect requires a governed migration. Freeze one exact C33-or-later candidate, reconstruct its package deterministically, qualify the exact package on the locked Factorio 2.1 environment, obtain normal manual and protected evidence, seal it, fast-forward `main`, publish it, and verify downloaded public bytes.

### T9-D: project and qualify the lower `.9` releases

After immutable `3.2.9` exists, materialize each lower integration from its exact `.5` predecessor and the immutable portable `.9` source. Require exact target-tree reconstruction, package identity, direct predecessor upgrade or transition proof where applicable, target-engine loads, target-tier qualification, tag integrity, and downloaded public-asset verification. Process targets in descending order: `2.5.9`, `1.9.9`, `1.8.9`, `1.7.9`, `1.6.9`, `1.5.9`, `1.4.9`, then `1.3.9`.

### T9-E: archive MIR 3 and hand off to MIR 4

When all admitted `.9` work is terminal, freeze the MIR 3 source, package, migration, compatibility, performance, evidence, and publication indexes. MIR 4 begins from that immutable handoff. Its offline release authority must make GitHub an idempotent publication channel rather than the sole build, qualification, or sealing authority.

## Release sequence

1. Maintain the `.5` tags and packages unchanged while package-excluded assurance debt is reconciled.
2. Freeze the unified finding inventory and target dispositions.
3. Implement portable corrections once on `dev`; keep target adapters explicit.
4. Assign a candidate only after exact source freeze.
5. Qualify and publish `3.2.9` through the normal release policy.
6. Materialize, qualify, and publish lower `.9` releases one at a time from immutable parents.
7. Stop only the affected target when its exact tree, package, transition, binary, tag, or public asset fails.
8. Freeze the completed terminal wave and open MIR 4 from the handoff packet.

## Gates

Every `.9` release requires:

- a typed ReleaseRecord and exact candidate identity assigned only at source freeze;
- an approved delta from its `.5` predecessor;
- deterministic source-tree and archive reconstruction;
- package composition and forbidden-entry checks;
- direct predecessor migration or transition proof where the target supports it;
- exact target-engine Base and applicable official-DLC loads;
- compatibility and performance evidence proportional to the affected surface;
- normal manual acceptance for the target tier;
- protected qualification and a non-revoked seal where policy requires them;
- immutable annotated tag, public release, downloaded-byte rehash, and target-engine public-asset smoke.

No `.5` publication exception automatically transfers to `.9`. Any new exception would require a separate release-specific maintainer decision that truthfully records the uncompleted gate.

## Hard stops

Stop the affected release when its predecessor identity is lost, the projected tree differs from the admitted tree, deterministic reconstruction differs, the exact target engine cannot load the package, direct transition evidence cannot be established, an existing tag conflicts, or public bytes differ from frozen local bytes.

Stop the whole wave when shared source custody is lost, `main` promotion would require rewriting public history, or a shared semantic defect invalidates the terminal family. A transport failure alone does not authorize rebuilding or moving a correct tag.

## Planning-point acceptance

This planning point is complete when the nine planned ReleaseRecords, current role pointers, branch policy, README, release indexes, Mod Portal copy, generated Control Plane views, and `MIR3-Terminal-ChangeSet` all name this programme and agree that:

- `.5` is current and immutable;
- `.9` is planned but not implemented;
- `.6` through `.8` do not exist;
- normal `.9` gates remain intact;
- every later MIR 3 correction has one target disposition;
- MIR 4 begins only after the `.9` archive and handoff.

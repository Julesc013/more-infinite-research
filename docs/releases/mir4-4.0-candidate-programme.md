---
title: "MIR 4.0 Candidate Programme"
status: current
applies_to: "MIR 4.0.0"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-24
supersedes:
  - docs/releases/mir4-bootstrap-local-beta-plan.md
superseded_by: []
source_of_truth_for:
  - mir4-4.0-product-contract
  - mir4-target-admission-model
  - mir4-candidate-wave-programme
  - mir4-4.0-definition-of-done
---

# MIR 4.0 Candidate Programme

## Product contract

MIR 4.0 is one source release with target-specific distribution versions. It combines a stable player product, a distributable developer-preview platform, and an executable shadow architecture. Maturity is per component, not a blanket claim over the repository.

| Layer | Public effect | 4.0 requirement |
| --- | --- | --- |
| Stable player product | May affect authoritative player behavior | Deterministic package, exact target engine, direct predecessor upgrade, two reloads, state/settings/research proof, manual acceptance, independent qualification and seal |
| Developer preview | Separate GitHub assets; no player ZIP content | Deterministic V1 archives, schema validation, examples, conformance, checksums, licensing and explicit V0-to-V1 migration policy |
| Shadow architecture | Reports and comparisons only | Deterministic execution and hard non-interference with prototypes, settings, migrations, persistent state and support claims |

The five governed maturity classes are Stable, Shadow, Preview, Experimental and Omitted by target. Anything below Stable cannot mutate authoritative player behavior or become required for loading a player package.

## Target set

| Target | Distribution | Predecessor | Candidate role | 4.0 admission rule |
| --- | --- | --- | --- | --- |
| F210 | `4.0.21000` | `3.2.11` | Mandatory | Must be fully qualified on exact Factorio 2.1.14 |
| F200 | `4.0.20000` | `2.5.11` | Mandatory | Must be fully qualified on exact Factorio 2.0.77 with maximum representable parity |
| F110 | `4.0.11000` | `1.9.9` | Conditional | Independent qualification or explicit deferral |
| F100 | `4.0.10000` | `1.8.9` | Conditional | Independent qualification or explicit deferral |
| F018 | `4.0.01800` | private 0.17 bridge | Experimental/private | No admission without an exact preserved 0.18 engine and full target-local proof |
| F017 | `4.0.01700` | `1.7.9` | Experimental/private | Private evidence only until all admission gates pass |
| F016 | `4.0.01600` | `1.6.9` | Experimental/private | Private evidence only until all admission gates pass |
| F015 | `4.0.01500` | `1.5.9` | Experimental/private | Private evidence only until all admission gates pass |
| F014 | `4.0.01400` | `1.4.9` | Experimental/private | Private evidence only until all admission gates pass |
| F013 | `4.0.01300` | `1.3.9` | Experimental/private | Private evidence only until all admission gates pass |

Padded historical distribution identities are canonical archive identities. Factorio 0.x may normalize the numeric patch component when displaying it in logs; evidence records both forms.

## 4.0 platform contents

The V1 developer preview includes nine copied, bounded APIs, JSON Schemas, Lua/LuaLS, TypeScript, Python and PowerShell bindings, canonicalization vectors, fixtures, generated reference, 12-kind MEP V1, V0-to-V1 migration helpers, a synthetic reference extension, Inspector, conformance runners, manifests, checksums, licensing and quickstarts. V0 remains a superseded compatibility input only. Player ZIPs exclude every developer and governance asset.

The executable shadow contains target-provider records, normalized compilation runs, FeatureManifest and SettingSpec projections, runtime/state inventories, ProcessIR facts, effect-channel inventory and diagnose-only synthesis opportunities. It serializes and compares the future architecture without becoming the emitter of record.

## Candidate waves

The current machine-readable pre-freeze cut, blockers, workflow maturity vocabulary, MIR 3 residual disposition, and dependency-ordered execution queue are owned by `.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Execution-ProgrammeV1.json`. Uploaded audits and handoff packages are hash-bound planning evidence only; repository authority and explicit human gates control execution.

| Wave | Purpose | Exit |
| --- | --- | --- |
| M4C01 | Historical bootstrap identifier, retained in immutable records only | Superseded by the unified whole-platform programme |
| M4C02 | Fix repository, authority and evidence closure | No authority drift or package-surface ambiguity |
| M4C03 | Harden target/normalized compiler and runtime cutover candidates | Parity reports complete; no authoritative cutover |
| M4C04 | Harden MEP, API, SDK and Inspector | Preview distribution and conformance complete |
| M4C05 | Expand ProcessIR, diagnose-only synthesis and historical shadows | Bounded opportunity and target-readiness catalogues |
| M4RC1 | Freeze the first release candidate | Exact tree and bytes eligible for independent production qualification |

Later `4.x` milestones graduate individual preview or shadow components; they are not the first time those components exist or can be tested.

## Post-4.0 graduation map

Every row below is present in 4.0 as stable infrastructure, a usable preview, or an executable shadow. These are evidence-driven graduation milestones, not promises that implementation is withheld until a later calendar release.

| Milestone | Graduation decision |
| --- | --- |
| 4.0.x | Stabilize released player targets and V1 developer feedback without broadening authority |
| 4.1 | Graduate the repository and release-engine fixed point |
| 4.2 | Graduate the target-provider ABI and affected-target planning |
| 4.3 | Graduate normalized contributions and merge-law proofs |
| 4.4 | Freeze compatible MEP/API/SDK 1.0 contracts |
| 4.5 | Admit certified synthesis classes from diagnose-only shadow mode |
| 4.6 | Graduate ProcessIR parity and bounded-loop safety |
| 4.7 | Cut over qualified runtime, state and migration ownership |
| 4.8 | Graduate Inspector and workbench workflows |
| 4.9+ | Admit named compatibility factories and independently proven historical targets |

A component may graduate earlier when its parity, safety, migration and target-local proof closes. No component becomes authoritative merely because a version number is reached.

## Branch and release flow

Normal work uses a short-lived branch and reviewed pull request into `dev`. A release freezes one exact `dev` tree, qualifies and seals that tree and its already-built bytes, promotes the identical tree to `main`, tags it, publishes the sealed bytes, redownloads them and verifies immutable receipts. Packages are never rebuilt after qualification. `legacy` remains the previous-major terminal authority.

This programme authorizes implementation, private candidates, runtime development evidence and reviewed integration into `dev`. It does not authorize production signing, production seals, tags, `main` or `legacy` promotion, GitHub release publication, Mod Portal upload or cleanup.

## Definition of done

Public 4.0 requires mandatory targets green; every conditional target either independently green or explicitly deferred; exact A/B/C identity; package exclusion proof; exact engine and predecessor locks; fresh loads; direct upgrades; two reloads; research/settings/state preservation; compatibility canaries; performance budgets; manual disposable-profile acceptance; independent verification; signatures and seals; two publication dry runs; clean restore; exact-tree promotion; public redownload and hash verification; player, developer, modder and maintainer documentation; and immutable continuity records.

No calendar deadline converts a missing proof into a pass.

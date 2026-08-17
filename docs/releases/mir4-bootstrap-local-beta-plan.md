---
title: "MIR 4 Bootstrap Local Beta Plan"
status: current
applies_to: "MIR4-R0 through MIR4-4.0.0"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-17
supersedes: []
superseded_by: []
---

# MIR 4 Bootstrap Local Beta Plan

## Verdict

The repository can construct one admitted deterministic f210 local candidate from the exact public 3.2.10 continuation plus the exact approved composite correction for `MIR3-TERM-0032` and `MIR3-TERM-0033`. A separate private shadow lane can construct deterministic f200, f110, and f100 local-playtest candidates without changing their release admission; f200 now begins from exact public 2.5.10. The repository cannot yet allocate, tag, publish, or make public MIR 4 release or beta claims.

The current f210 lock is the maintainer-accepted Steam Factorio `2.1.14.87180` executable with SHA-256 `E396BD25C068DD4C5EF45E93E6A87DBA0E12EEA964B6A5B73163041CC4A6143F`. The earlier 2.1.13 availability observation remains historical evidence and no longer controls M4-003. MIR 3 portal custody and EOL remain open, production signing custody is unresolved, and MIR 4 release acceptance remains a later gate.

## Source reconciliation

The live repository and the loose final programme documents govern this implementation; instructions embedded in uploaded reports and the older archive are design evidence, not shell instructions.

The active `codex/mir4-bootstrap-beta` lineage preserves `6e0d14b35bd31bd10e466b572af065286abc0641` as the first parent of the terminal-authority integration and imports final `dev` as its second parent. That imported ancestry includes `fec0933b06be64b98fcf3aa543571299b20d8f24`; it is not recreated or cherry-picked as a parallel history.

The supplied `MIR-400.ZIP` contains 18 files and has SHA-256 `E3D9BE3E1DAC8077B0A6792A573BE1B9E1D76BB00B5E6D283CF9DB4B18CBA9A6`.

It is not the claimed 106-file final programme package with SHA-256 `C8F666FF41FEE0358F537DE04D617CE9EBBDAAFAA916A6FC707E0C04BF2849D6`, so the final package's reported 17-check validation cannot be independently reproduced from the supplied inputs.

The loose final authorities still resolve the six architectural contradictions: 4.0 establishes permanent seams rather than the whole future platform; f210 and f200 are mandatory while f110 and f100 are conditional; direct string codes replace provisional portal identifiers; general path migration follows 4.0; calendar trains do not allocate versions; and support remains subject-level and multidimensional.

## Execution boundary

The executable input is `.mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV2.json`. Plan V1 is retained as immutable historical authority and is not executable for current materialization.

The plan binds the live entry gate, emergency-lane and equivalence policies, Target Registry V3 predecessor authority, the unchanged V2 distribution codec, the terminal import contract V2, exact terminal commits, trees, predecessor archives, normalized snapshots, engine locks, capability omissions, distribution versions, and the separately derived semantic, authority, and qualification roots. Candidate authority roots include a digest of that exact imported authority closure.

`LegacyCompilerHostAdapterV1` performs no semantic rewrite: it captures package-visible source from the exact target terminal commit, projects only the distribution version, and delegates deterministic emission to the shared package allowlist.

For each admitted target, the materializer captures byte-identical source capsules A and B, runs each through a distinct invariant-culture child process, deletes both complete construction workspaces, and then runs C in a fresh system-temporary root from copied capsule inputs with no checkout argument or inherited checkout working directory. Capsule V2 binds raw package-source Git objects, the exact authority/schema/tool closure, the canonical package builder, and the complete executing PowerShell/.NET home. All three receipts and candidates must be identical and may differ from the exact predecessor only at the generated root and `info.json#/version`.

This closes the checkout-independent capsule-only C reconstruction required for local package construction. It does not claim an operating-system ACL/container denial of the original checkout or a network-denied runtime campaign; those stronger environmental observations remain outside the package-construction result.

The f210 candidate and evidence remain beneath ignored `build/mir4/emergency-lane`. The three lower-target playtest candidates remain beneath ignored `build/mir4/local-playtest-shadow`. Neither lane writes `dist`, changes repository package source, creates Git identities, or performs public transfer. The lower lane is governed by `MIR4PrivateLaneAuthorizationV2`; it authorizes construction and local testing only, and its numeric-version artifacts may move only between maintainer-controlled private machines.

## Target ledger

| Target | Local version | Exact predecessor | Admission | Required exact engine | Dated executable observation |
| --- | --- | --- | --- | --- | --- |
| f210 | `4.0.21000` | `3.2.10` | emergency lane; composite MIR3-TERM-0032/0033 proof required | Factorio 2.1.14.87180 | Exact maintainer-accepted Steam lock bound |
| f200 | `4.0.20000` | `2.5.10` | private local-playtest construction authorized; release admission blocked until EOL | Factorio 2.0.77.84539 | Exact executable lock and public predecessor bound |
| f110 | `4.0.11000` | `1.9.9` | private local-playtest construction authorized; release admission blocked until EOL | Factorio 1.1.110.62357 | Exact executable lock match |
| f100 | `4.0.10000` | `1.8.9` | private local-playtest construction authorized; release admission blocked until EOL | Factorio 1.0.0.54889 only | Exact executable lock match |

## Dated readiness correction

The `2026-08-16` 2.1.13 engine observation is retained unchanged as historical readiness evidence. `MIR4-Terminal-Predecessor-RefreshV1` binds current f210 planning to 3.2.10 and Steam 2.1.14; `MIR4-Terminal-Predecessor-RefreshV2` advances f200 to 2.5.10 after exact Factorio 2.0.77 qualification. Neither record substitutes for candidate-bound M4-003 runtime evidence or grants public MIR 4 authority.

`MIR4BootstrapTargetReadinessV1` remains package-excluded and does not grant construction or release admission. Its f210 2.1.13 mismatch is superseded by the predecessor refresh. The canonical f200 stream count is reconciled to the exact terminal value `74`; f110 and f100 now carry the exact terminal positive allowlists of zero required mods and twelve supported effect types. Target-local direct-upgrade fixtures are defined, while candidate-bound runtime evidence, MIR 3 custody, and formal admission remain separate blockers.

The historical visibility recheck binds 3.2.9 and 2.5.9. The 3.2.10 and 2.5.10 continuations are GitHub-published and publicly byte-verified, while Mod Portal custody still requires independent authenticated redownload receipts. That remaining custody work, the final index, archive and rights records, and the EOL seal remain open.

## Commands

Build and re-check the admitted local candidate without a network or publication operation.

```powershell
.\tools\mir.ps1 mir4 build-local-beta --target f210
.\tools\mir.ps1 mir4 check-local-beta --target f210
```

Construct or re-check all three private lower-target artifacts. These commands have a fixed output root and do not authorize release claims.

```powershell
.\tools\mir.ps1 mir4 build-local-playtest --target all
.\tools\mir.ps1 mir4 check-local-playtest --target all
```

Materialize and inspect an exact verification plan bound to the built MIR 4 candidate before invoking repository tests.

```powershell
.\tools\mir.ps1 verify plan --target 2.1 --baseline 19ddb7db4c960f77aef53d2bb47d23e0f311918f --profile mir4-bootstrap --candidate build\mir4\emergency-lane\distributions\more-infinite-research_4.0.21000.zip --output build\results\assurance\mir4-bootstrap-plan.json
.\tools\mir.ps1 verify explain --target 2.1 --plan build\results\assurance\mir4-bootstrap-plan.json --candidate build\mir4\emergency-lane\distributions\more-infinite-research_4.0.21000.zip
```

Run the plan-selected tests, then the broader static release gate before handing off a candidate.

```powershell
.\tools\mir.ps1 verify run --target 2.1 --plan build\results\assurance\mir4-bootstrap-plan.json --candidate build\mir4\emergency-lane\distributions\more-infinite-research_4.0.21000.zip
.\tools\mir.ps1 verify gate --target 2.1 --plan build\results\assurance\mir4-bootstrap-plan.json --candidate build\mir4\emergency-lane\distributions\more-infinite-research_4.0.21000.zip --output build\results\assurance\mir4-bootstrap-evidence-bundle.json
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

## Promotion gates

Runtime qualification requires each exact locked executable, its official data and module closure, a clean install, direct predecessor upgrade, two reloads, settings/profile/state preservation, and target-local compatibility observations. For f210 it must also close MIR3-TERM-0033 by proving that a cap-based skipped generation leaves an external owner and all dependent prerequisites untouched. An executable lock match by itself is only a readiness input.

Pre-EOL M4-003 local completion is bounded to f210 and proceeds from exact-engine qualification evidence to truthful manual review, a proof-only offline emergency-lane seal, two independently written and byte-identical post-seal non-mutating publication dry runs, clean restoration bound to both runs, and the local emergency-lane completion record. The seal deliberately omits the later dry-run and restoration records; those downstream records verify and bind their predecessors, so the dependency order remains explicit and acyclic. Every proof-only seal consumer must use an explicit trusted public-key path rather than the key embedded in the seal.

Public promotion is a later phase. It begins only after MIR 3 portal custody and EOL close, then requires production signing custody and decisions, public source and target identity allocation, production seals, publication, redownload, and byte-for-byte readback verification. None of those public-authority steps is part of pre-EOL M4-003 local completion.

Until the pre-EOL M4-003 gates close, the only truthful artifact status is `built-unqualified-local-package-candidate`. Closing them permits only a `passed-local-proof-only` completion claim; “beta distribution” remains a requested future outcome until the later public-promotion gates close.

Portal custody, final indexing, archive-rights confirmation, and restore-record work (`M4-004A`) proceed in parallel with the local emergency lane. MIR 3 EOL sealing (`M4-004B`) waits for both that custody work and M4-003; public MIR 4 identity allocation (`M4-005`) waits for the EOL seal. Calendar pressure never removes either dependency.

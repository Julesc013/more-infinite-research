---
title: "Native Owner Backport Ledger"
status: current
applies_to: "2.4.0 through Factorio 0.6"
audience: release-manager
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-14
supersedes: []
superseded_by: []
---

# Native Owner Backport Ledger

This ledger carries the observable native-owner settings contract down the release wave. It is a sequencing and evidence obligation, not advance authority to mutate older branches. Each line starts only after the preceding candidate is tagged and released by the maintainer.

| Order | Factorio | MIR release | Branch | Required adaptation | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | 2.0 | 2.4.0 | `tmp/2.0`, then `legacy` | Four Space Age native recipe-productivity owners, full settings and transaction matrix | In qualification |
| 2 | 1.1 | 1.9.4 | `tmp/1.1` | Re-probe owners and formula shapes; retain stable setting IDs; generate when no eligible native owner exists | Paused until 2.4.0 release |
| 3 | 1.0 | 1.8.2 | `tmp/1.0` | Target-local owner discovery and Lua/runtime adapters | Paused |
| 4 | 0.17 | 1.7.1 | `tmp/0.17` | Native-infinite capabilities only; no recipe-productivity claim where the target lacks it | Paused |
| 5 | 0.16 | 1.6.0 | `tmp/0.16` | Old-science and prototype-schema adapters; generated or finite fallback as target facts require | Paused |
| 6 | 0.15 | 1.5.0 | `tmp/0.15` | Minimal native-infinite surface with target-binary proof | Paused |
| 7 | 0.14 | 1.4.0 | `tmp/0.14` | Finite-ladder fallback and target-era settings registration | Paused |
| 8 | 0.13 | 1.3.0 | `tmp/0.13` | Finite-ladder fallback and target-era settings registration | Paused |
| 9 | 0.12 through 0.6 | target release version | matching `tmp/<line>` | Discovery first; preserve the player-facing intent only where the target can represent it safely | Paused |

## Portable Obligations

- One stable stream settings surface governs generated, adopted, already-covered, and safe fallback outcomes.
- Defaults preserve the target's final native or modded owner balance exactly; disabled streams do not touch external owners.
- Explicit overrides use only target-proven formula adapters and relevant effects. Unsafe formulas reject instead of being rewritten heuristically.
- A complete plan validates owner uniqueness and input/output fingerprints before the emission boundary mutates a prototype.
- Every target receives its own fixtures, binary evidence, upgrade/settings-retention proof, deterministic package, and candidate seal. Evidence from Factorio 2.0 is never substituted for an older line.
- Where a target has no recipe-productivity technology effect, the backport preserves the configurability goal through the closest safe generated or finite technology contract and records the capability cut honestly.

The authoritative branch order remains `.mir/release-wave.yml`. No work on `tmp/1.1` or below is authorized by completing this document.

---
title: "MIR 3 Terminal Wave Dashboard"
status: current
applies_to: "3.2.5 through terminal .9 releases"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-08
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-3-terminal-wave-dashboard
---

# MIR 3 Terminal Wave Dashboard

The [MIR 3 terminal `.9` programme](mir-3-terminal-dot-9-programme.md) is the planning authority. Typed ReleaseRecords are the state authority. This page is a human-readable projection.

| Target | Frozen public release | Planned terminal release | Candidate floor | Planning state |
| --- | --- | --- | --- | --- |
| Factorio `2.1` | `3.2.5` / C32 | `3.2.9` | C33 | Planning only |
| Factorio `2.0` | `2.5.5` / `2.5-P12` | `2.5.9` | `2.5-P13` | Planning only |
| Factorio `1.1.110` | `1.9.5` | `1.9.9` | `1.9-P1` | Planning only |
| Factorio `1.0.0` only | `1.8.5` | `1.8.9` | `1.8-P1` | Planning only |
| Factorio `0.17.79` | `1.7.5` | `1.7.9` | `1.7-P1` | Planning only |
| Factorio `0.16.51` | `1.6.5` | `1.6.9` | `1.6-P1` | Planning only |
| Factorio `0.15.40` | `1.5.5` | `1.5.9` | `1.5-P1` | Planning only |
| Factorio `0.14.23` | `1.4.5` | `1.4.9` | `1.4-P1` | Planning only |
| Factorio `0.13.20` | `1.3.5` | `1.3.9` | `1.3-P1` | Planning only |

## Current gate

No `.9` implementation is admitted. First reconcile retained package-excluded `.5` assurance debt and freeze one finding inventory with a target-by-target disposition. Only then may `3.2.9` source work begin on `dev`.

## Fixed rules

- Published `.5` tags and packages are immutable.
- `.6`, `.7`, and `.8` are prohibited.
- Lower targets materialize independently from their exact `.5` predecessor plus the immutable portable `.9` source.
- `1.8.9` targets Factorio `1.0` only; it does not claim Factorio `0.18` support.
- `.9` releases use normal qualification and sealing rules unless a new, truthful, release-specific decision explicitly says otherwise.
- MIR 4 starts only after the terminal wave is archived and handed off.

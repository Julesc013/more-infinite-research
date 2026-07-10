---
title: "3.0.5 Backport Behavior Ledger"
status: current
applies_to: "3.0.5"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-10
supersedes: []
superseded_by: []
---

# 3.0.5 Backport Behavior Ledger

This ledger translates historical branch work into observable contracts. The
machine-readable authority is `.mir/convergence.yml`. Historical commit order
does not grant implementation authority; `dev` remains canonical.

| ID | Source | Observable contract | Class | Decision | Evidence | Status |
| --- | --- | --- | --- | --- | --- | --- |
| BP-001 | `1.7.0@1a9b5a7` | Preserve exact release provenance | A | Record evidence only | branch manifest and archive hash | Complete |
| BP-002 | `1.7.0@1a9b5a7` | Enabled science recipes gain no disabled unlock gate | B | Adapt in science capability | generated-prerequisite fixture | Complete |
| BP-003 | `1.7.0@1a9b5a7` | Emitted prerequisites are enabled, acyclic, and reachable | B | General invariant | data and runtime graph fixture | Complete |
| BP-004 | all target rings | Lua and validation use one target profile authority | C | Centralize and generate | drift check | Complete |
| BP-005 | 1.9.3 through 1.7.0 | Target explicitly selects `storage` or `global` | C | Platform adapter | architecture lint | Complete |
| BP-006 | all target rings | Scenarios have groups, durations, and durable partial results | C | Extract runner seams | structured summary | Complete |
| BP-007 | reduced target rings | Reduced setting visibility is not codec coverage | C | Split fixture | two named gates | Complete |
| BP-008 | 1.7.0 | Conditional weapon cleanup requires replacement coverage | C | Adapt owner policy | six-case matrix plus external owner | Complete |
| BP-009 | `dev@b9b1abc` | Dedicated weapon streams retain target progression gates | A | Keep modern implementation | generation integrity | Complete |
| BP-010 | `tmp/0.17` | 0.17 metadata and reduced defaults stay target-local | E | Reject from dev | branch policy | Complete |
| BP-011 | generic convergence proposal | Host plugin registry and lifecycle | F | Defer to 3.1+ | future ADR required | Deferred |
| BP-012 | planned 0.16 ring | Old science roles map to old prototype IDs | F | Defer to `tmp/0.16` | 0.16 binary proof | Deferred |
| BP-013 | dev audit | Planning and public docs match current evidence | B | Reconcile | governance lint | Complete |

## Classification Rules

- A: modern behavior already exists; retain only useful evidence.
- B: behavior is missing and compatible; implement at the current boundary.
- C: behavior is partial; define one combined contract and implementation.
- D: an external legacy contract needs an adapter or migration.
- E: behavior is accidental, obsolete, or target-local; reject from `dev`.
- F: behavior changes the public contract or belongs to a future target/release.
- G: behavior is unknown and cannot be integrated until investigated.

Every accepted row must end with one canonical implementation and named
evidence. Target metadata, dependency floors, science IDs, assets, and disabled
modern surfaces never qualify as portable behavior by themselves.

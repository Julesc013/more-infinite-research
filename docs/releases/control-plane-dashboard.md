---
title: "MIR Control Plane Dashboard"
status: current
applies_to: "release-engineering"
audience: release-manager
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-07
supersedes: []
superseded_by: []
---

# MIR Control Plane Dashboard

> Generated from `path:releases.records/*.json`, CandidateClosureRecords, ChangeRecords, IncidentRecords, and TaskNodes. Machine records are authoritative.

## Releases

| Release | Candidate | Reserved floor | Target | Branch | Historical state | Effective status | Exceptions |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| `3.2.5` | `C32` | `C32` | `2.1` | `dev` | `manually-accepted` | `manually-accepted` | 1 |
| `3.2.4` | `C31` | `pending` | `2.1` | `dev` | `package-built` | `superseded-unpublished` | 0 |
| `3.2.3` | `C30` | `pending` | `2.1` | `main` | `publicly-verified` | `publicly-verified` | 1 |
| `3.2.2` | `C24` | `pending` | `2.1` | `main` | `tagged` | `tagged` | 1 |
| `3.2.1` | `C21` | `pending` | `2.1` | `main` | `published` | `published` | 1 |
| `2.5.0` | `2.5-P11` | `pending` | `2.0` | `legacy` | `publicly-verified` | `publicly-verified` | 1 |
| `2.4.9` | `2.4.9-final` | `pending` | `2.0` | `legacy` | `publicly-verified` | `publicly-verified` | 1 |

A state is an admitted fact, not a mutable job status. Every later transition requires its own immutable proof record.

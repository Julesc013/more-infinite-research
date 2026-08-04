---
title: "MIR Control Plane Dashboard"
status: current
applies_to: "release-engineering"
audience: release-manager
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-04
supersedes: []
superseded_by: []
---

# MIR Control Plane Dashboard

> Generated from `path:releases.records/*.json`, ChangeRecords, IncidentRecords, and TaskNodes. Machine records are authoritative.

## Releases

| Release | Candidate | Reserved floor | Target | Branch | State | Exceptions |
| --- | --- | --- | --- | --- | --- | ---: |
| `3.2.5` | `not-assigned` | `C32` | `2.1` | `dev` | `planned` | 0 |
| `3.2.4` | `C31` | `pending` | `2.1` | `dev` | `package-built` | 0 |
| `3.2.3` | `C30` | `pending` | `2.1` | `main` | `publicly-verified` | 1 |
| `3.2.2` | `C24` | `pending` | `2.1` | `main` | `tagged` | 1 |
| `3.2.1` | `C21` | `pending` | `2.1` | `main` | `published` | 1 |
| `2.5.0` | `2.5-P11` | `pending` | `2.0` | `legacy` | `publicly-verified` | 1 |
| `2.4.9` | `2.4.9-final` | `pending` | `2.0` | `legacy` | `publicly-verified` | 1 |

A state is an admitted fact, not a mutable job status. Every later transition requires its own immutable proof record.

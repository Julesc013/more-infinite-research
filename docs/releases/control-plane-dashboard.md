---
title: "MIR Control Plane Dashboard"
status: current
applies_to: "release-engineering"
audience: release-manager
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-16
supersedes: []
superseded_by: []
---

# MIR Control Plane Dashboard

> Generated from `path:releases.records/*.json`, CandidateClosureRecords, ChangeRecords, IncidentRecords, and TaskNodes. Machine records are authoritative.

## Releases

| Release | Candidate | Namespace / minimum next ordinal | Target | Branch | Historical state | Effective status | Exceptions |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| `3.2.10` | `C34` | `C / 34` | `2.1` | `main` | `package-built` | `package-built` | 0 |
| `3.2.9` | `C33` | `C / 33` | `2.1` | `main` | `publicly-verified` | `publicly-verified` | 0 |
| `3.2.5` | `C32` | `C32` | `2.1` | `main` | `publicly-verified` | `publicly-verified` | 1 |
| `3.2.4` | `C31` | `pending` | `2.1` | `dev` | `package-built` | `superseded-unpublished` | 0 |
| `3.2.3` | `C30` | `pending` | `2.1` | `main` | `publicly-verified` | `publicly-verified` | 1 |
| `3.2.2` | `C24` | `pending` | `2.1` | `main` | `tagged` | `tagged` | 1 |
| `3.2.1` | `C21` | `pending` | `2.1` | `main` | `published` | `published` | 1 |
| `2.5.10` | `not-assigned` | `2.5-P / 14` | `2.0` | `legacy` | `planned` | `planned` | 0 |
| `2.5.9` | `2.5-P13` | `2.5-P / 13` | `2.0` | `legacy` | `publicly-verified` | `publicly-verified` | 0 |
| `2.5.5` | `2.5-P12` | `pending` | `2.0` | `legacy` | `publicly-verified` | `publicly-verified` | 1 |
| `2.5.0` | `2.5-P11` | `pending` | `2.0` | `legacy` | `publicly-verified` | `publicly-verified` | 1 |
| `2.4.9` | `2.4.9-final` | `pending` | `2.0` | `legacy` | `publicly-verified` | `publicly-verified` | 1 |
| `1.9.9` | `1.9-P1` | `1.9-P / 1` | `1.1` | `tag-only` | `publicly-verified` | `publicly-verified` | 0 |
| `1.9.5` | `1.9.5-final` | `pending` | `1.1` | `tag-only` | `publicly-verified` | `publicly-verified` | 1 |
| `1.8.9` | `1.8-P1` | `1.8-P / 1` | `1.0` | `tag-only` | `publicly-verified` | `publicly-verified` | 0 |
| `1.8.5` | `1.8.5-final` | `pending` | `1.0` | `tag-only` | `publicly-verified` | `publicly-verified` | 1 |
| `1.7.9` | `1.7-P1` | `1.7-P / 1` | `0.17` | `tag-only` | `publicly-verified` | `publicly-verified` | 0 |
| `1.7.5` | `1.7.5-final` | `pending` | `0.17` | `tag-only` | `publicly-verified` | `publicly-verified` | 1 |
| `1.6.9` | `1.6-P1` | `1.6-P / 1` | `0.16` | `tag-only` | `publicly-verified` | `publicly-verified` | 0 |
| `1.6.5` | `1.6.5-final` | `pending` | `0.16` | `tag-only` | `publicly-verified` | `publicly-verified` | 1 |
| `1.5.9` | `1.5-P1` | `1.5-P / 1` | `0.15` | `tag-only` | `publicly-verified` | `publicly-verified` | 0 |
| `1.5.5` | `1.5.5-final` | `pending` | `0.15` | `tag-only` | `publicly-verified` | `publicly-verified` | 1 |
| `1.4.9` | `1.4-P1` | `1.4-P / 1` | `0.14` | `tag-only` | `publicly-verified` | `publicly-verified` | 0 |
| `1.4.5` | `1.4.5-final` | `pending` | `0.14` | `tag-only` | `publicly-verified` | `publicly-verified` | 1 |
| `1.3.9` | `1.3-P1` | `1.3-P / 1` | `0.13` | `tag-only` | `publicly-verified` | `publicly-verified` | 0 |
| `1.3.5` | `1.3.5-final` | `pending` | `0.13` | `tag-only` | `publicly-verified` | `publicly-verified` | 1 |

A state is an admitted fact, not a mutable job status. Every later transition requires its own immutable proof record.

## Terminal .5 semantic baselines

Queue status: `complete-all-nine-realized-and-reconciled`. All nine exact-engine semantic baselines are complete and reconciled.

| Predecessor | Terminal release | Target | Identity | Semantic inventory | Manifest |
| --- | --- | --- | --- | --- | --- |
| `3.2.5` | `3.2.9` | `2.1` | `locked` | `complete` | `.mir/releases/terminal/baselines/3.2.5/baseline-manifest.json` |
| `2.5.5` | `2.5.9` | `2.0` | `locked` | `complete` | `.mir/releases/terminal/baselines/2.5.5/baseline-manifest.json` |
| `1.9.5` | `1.9.9` | `1.1.110` | `locked` | `complete` | `.mir/releases/terminal/baselines/1.9.5/baseline-manifest.json` |
| `1.8.5` | `1.8.9` | `1.0.0-only` | `locked` | `complete` | `.mir/releases/terminal/baselines/1.8.5/baseline-manifest.json` |
| `1.7.5` | `1.7.9` | `0.17.79` | `locked` | `complete` | `.mir/releases/terminal/baselines/1.7.5/baseline-manifest.json` |
| `1.6.5` | `1.6.9` | `0.16.51` | `locked` | `complete` | `.mir/releases/terminal/baselines/1.6.5/baseline-manifest.json` |
| `1.5.5` | `1.5.9` | `0.15.40` | `locked` | `complete` | `.mir/releases/terminal/baselines/1.5.5/baseline-manifest.json` |
| `1.4.5` | `1.4.9` | `0.14.23` | `locked` | `complete` | `.mir/releases/terminal/baselines/1.4.5/baseline-manifest.json` |
| `1.3.5` | `1.3.9` | `0.13.20` | `locked` | `complete` | `.mir/releases/terminal/baselines/1.3.5/baseline-manifest.json` |

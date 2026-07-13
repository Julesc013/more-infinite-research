---
title: "MIR 2.4.0 Legacy Backport Wave Handoff"
status: draft
applies_to: "1.9.4 through 1.3.0"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-14
supersedes: []
superseded_by: []
---

# MIR 2.4.0 Legacy Backport Wave Handoff

This tracked handoff covers the independent release candidates for Factorio 1.1, 1.0, 0.17, 0.16, 0.15, 0.14, and 0.13. It records implementation, exact artifact, validation, seal, and future release-command authority without publishing any candidate.

The published MIR 3.1.5 and MIR 2.4.0 archives are immutable campaign anchors. The public MIR 2.4.0 GitHub asset was independently downloaded and matched SHA-256 `4BA19EA071E6359BC25C58CCD8F65CAF81B4AA675496E2F53175A996C791470C`. Later target branches reconcile the published state without modifying those bytes.

## Campaign Status

| Order | Factorio | MIR | Branch | Status |
| ---: | --- | ---: | --- | --- |
| 1 | 1.1 | 1.9.4 | `tmp/1.1` | `FAIL-FIXING` |
| 2 | 1.0 | 1.8.2 | `tmp/1.0` | `FAIL-FIXING` |
| 3 | 0.17 | 1.7.1 | `tmp/0.17` | `FAIL-FIXING` |
| 4 | 0.16 | 1.6.0 | `tmp/0.16` | `FAIL-FIXING` |
| 5 | 0.15 | 1.5.0 | `tmp/0.15` | `FAIL-FIXING` |
| 6 | 0.14 | 1.4.0 | `tmp/0.14` | `FAIL-FIXING` |
| 7 | 0.13 | 1.3.0 | `tmp/0.13` | `FAIL-FIXING` |

All tags, GitHub releases, Mod Portal uploads, and public publication commands remain `NOT-RUN`. Manual visual review remains `PENDING-MAINTAINER`.

Detailed machine-readable state is in `.mir/evidence/backport-wave-2.4.0/campaign.json`. This document will become the complete ordered morning release packet after the convergence sweep.

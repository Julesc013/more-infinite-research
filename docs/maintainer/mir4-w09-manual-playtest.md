---
title: "MIR 4 W09 Manual Playtest Handoff"
status: current
applies_to: "4.0.0 M4C02-09-24H"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-23
supersedes: []
superseded_by: []
---

# MIR 4 W09 Manual Playtest Handoff

Use this after the automated campaign is green and before any source freeze or release decision. The current W09 result is private and unqualified; this checklist does not authorize publishing.

## Inputs to verify

1. Confirm the checked-out commit and tree match both W09 output records.
2. Confirm the candidate ZIP SHA-256 matches `MIR4_PRIVATE_PACKAGE_MATRIX.json` for the target being tested.
3. Confirm Factorio reports the exact governed engine patch. Use Steam only for current Factorio 2.1; use `D:\Programs\Factorio\<version>` for 2.0 and every older engine.
4. Keep a fresh isolated user-data directory and retain the complete log and save artifacts.

## Modern targets

For f210 and f200, start a new game with default settings, inspect the technology graph, research representative mining/productivity/weapon/lab continuations, save, reload twice, and directly upgrade one representative MIR3 save. Repeat any target-specific affected scenario named by the final verification plan. Record UI presentation, costs, prerequisites, effects, disabled/hidden state, mod-data diagnostics, and any unexpected warnings.

For f110 and f100, verify the reduced capability surface: no modern-only setting or effect appears, finite substitutes remain finite, locales load, and fresh-load plus repeat-load behavior matches the manifest omissions.

## Historical targets

For f017 through f013, use only the exact engine named by the authorization. Check the dedicated runtime receipt first, then manually inspect the direct predecessor upgrade and two candidate reloads. f018 remains blocked unless the governed exact 0.18 engine is supplied and hash-locked; do not substitute 0.17 or a nearby 0.18 patch.

## Museum inventory

Treat f012 through f006 as restoration experiments, not MIR4 support. Do not move archives into a release set. Record exact executable/base-data hashes, archive hash, isolated install outcome, and configuration restoration. A successful local launch does not clear rights, custody, mirror, or restore-closure blockers.

## Failure capture and decision

On any mismatch, stop promotion, preserve the exact candidate and environment identity, save logs/screenshots/saves, and record the smallest reproducer. Do not repair evidence in place. After review, the maintainer may accept a new bounded candidate, request a fix and full affected revalidation, or retain `PARTIAL-WITH-BOUNDED-BLOCKERS`. Source freeze, signing, sealing, tagging, merge to main, and publication remain separate human-authorized actions.

---
title: "MIR 4 Qualification and Promotion"
status: current
applies_to: "MIR 4.0.0 and later"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-18
supersedes: []
superseded_by: []
---

# MIR 4 Qualification and Promotion

## Candidate closure

1. Materialize the verification plan for the exact target, candidate hash, engine lock and repository tree.
2. Reuse evidence only when the complete trusted fingerprint matches; adopt an exact in-progress worker instead of starting a duplicate.
3. Run narrow contract and package checks before the broader static gate.
4. Prove deterministic A/B/C archives and exact package exclusion.
5. Run fresh load, direct predecessor upgrade, two upgraded-save reloads, settings/research/state checks, compatibility canaries and performance.
6. Record manual disposable-profile acceptance separately from automation.
7. Independently verify the aggregate evidence rather than trusting job status.

## Freeze

Freeze one exact `dev` commit and tree. After freeze, only release-blocking fixes are allowed; every fix invalidates the affected proof. No package-visible documentation or architecture work may be added after the final candidate bytes are qualified.

## Production authorization

Production work requires a separate explicit go/no-go. It covers signing identity and custody, final target admission, exact package seals, two independent publication dry runs, restore proof, `main` promotion, tags, GitHub assets and Mod Portal uploads. The promotion tree must equal the sealed tree and the packages must not be rebuilt.

## Publication and readback

GitHub receives player packages, preview developer assets, checksums, manifests, signatures, release notes and the target matrix. Mod Portal receives player packages and target-aware player copy only. After publication, authenticated redownload, hash, archive root, metadata and exact-engine smoke must match the sealed bytes before an immutable receipt closes the release.

## Hotfix

Branch from the published `main` commit or tag, calculate the affected target set, run target-local proof, publish only affected target bytes, record new immutable receipts and forward-port the fix to `dev`. Do not create permanent target branches or manually rebuild historical packages.

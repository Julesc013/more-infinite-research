---
title: MIR 4.2 nine-target rehearsal input gap
description: Candidate-bound inputs required before an executable nine-target release rehearsal.
---

# MIR 4.2 nine-target rehearsal input gap

The active release-cut authority is `.mir/releases/governance/mir4/MIR42-Nine-Target-Release-Cut-ProgrammeV1.json`. It selects `f210`, `f200`, `f110`, `f100`, `f017`, `f016`, `f015`, `f014`, and `f013`, but declares the 4.2 candidate **unallocated** and `exact_candidate_required: true`.

No rehearsal may claim package, save-upgrade, or performance results for a mutable development tree. Create the candidate authority first, then bind every run to its archive and content hashes and to the direct predecessor authority `.mir/releases/governance/mir4/MIR42-Direct-Predecessor-InputsV1.json` (record SHA-256 `CCE27120FACD744993D903CAD8F4B0355A2397F3DEB607D2311977446767B36C`).

After candidate allocation, execute the target compiler and the candidate-bound campaign through the repository release command selected by the verification plan. Capture each target's exact engine version, mod set, predecessor save identity, candidate archive hash, package-content hash, result, and log hash. Do not start Factorio before those identities exist.

This is a pre-freeze rehearsal-input disposition. It neither allocates a candidate nor authorizes source freeze, signing, tagging, publication, or promotion.

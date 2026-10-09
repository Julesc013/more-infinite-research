---
title: "Maximum-Level Binding Contract"
status: current
applies_to: "current F210 and F200 schema-3 maximum-level policy"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-09-22
supersedes:
  - "current composed V2 publication"
  - "progression PR #286 implementation placeholder"
superseded_by: []
source_of_truth_for:
  - current-maximum-level-binding-policy-v3
---

# Maximum-Level Binding Contract

`MIRMaximumLevelPolicyV3` is the active package contract for F210 and F200. F210 transports the policy through mod-data and fails closed when that modern transport is missing, malformed, or finalizer-blocked. F200 has no mod-data prototype surface and reconstructs the same schema-3 policy from governed startup settings. F110 and F100 deliberately omit the script-owned binding module.

The schema-3 port was integrated through PR #299 and its current-source harness corrections through PRs #315, #322, and #324. The old PR #286 branch is closed and unmerged; its parallel `src` tree must not be rebased, cherry-picked, or merged into the canonical `source/` implementation. V2 transport remains accepted only as a read-only migration input for authentic predecessors.

This source contract is implemented, but candidate qualification is still open. Current-head F210 and F200 ownership, settings changes, force/reset behavior, queues, nonzero progress, and V2-to-V3 migration require their exact governed engine evidence before a release claim.

`MIRMaximumLevelPolicyV3` is the one maximum-level registry for MIR-generated technologies, base continuations, and adopted native owners. Every managed technology has at most one normalized schema-3 `MaximumLevelBinding`.

## Resolution

Bindings resolve in this order: exact technology, exact native owner, exact stream, family, ecosystem profile, then global. Two conflicting candidates at the same precedence are a blocking conflict; source iteration order never chooses the winner.

Each binding records the technology ID, semantic stream and family IDs, binding source and operation, setting name and effective profile, requested cap, effective cap, prototype/runtime/presentation strategies, target requirements, finalizer observation, migration behavior, stable diagnostics, and provenance fingerprint.

## Cap Semantics

A cap of `0` means infinite. A positive cap is the absolute highest research level, not a count of additional levels. On script-capable targets, finite bindings retain an infinite prototype and enforce the cap at runtime so a configuration change cannot destroy completed levels or bonuses.

Runtime removes only invalid current or queued levels above the effective cap. It retains valid research progress and all completed levels and bonuses. Raising or removing a cap restores only technologies MIR previously disabled; unrelated mod state is not overwritten.

The completed capped technology remains visible and completed. Its infinity badge is hidden and its localized description states the exact effective cap.

## Finalizer Safety

The presentation pass records the known `factorio-data-final-fixes-v1` observation before publishing the registry through mod-data. A missing observation, finite late prototype maximum, equal-precedence conflict, or unknown finalizer adapter produces a stable blocking diagnostic. Runtime refuses queue normalization for that binding rather than guessing.

The pure compiler fixture proves normalization, precedence, order independence, known-finalizer acceptance, and unknown-finalizer rejection. The governed `local-2-1-corrundum-maxcap-13` campaign remains historical characterization at pinned commit `297aa5cc902da96847165a4f9caa1048608839fb`: it machine-checks one exact repair record, nine cap-13 runtime bindings, and the absence of maximum-level conflicts on Factorio `2.1.14` with exact `PlanetsLib_1.19.5` and `corrundum_1.0.47` archives. It is not current-candidate qualification.

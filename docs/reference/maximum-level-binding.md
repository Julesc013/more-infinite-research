---
title: "Maximum-Level Binding Contract"
status: current
applies_to: "4.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-21
supersedes: []
superseded_by: []
source_of_truth_for:
  - maximum-level-binding-policy-v3
---

# Maximum-Level Binding Contract

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

The pure compiler fixture proves normalization, precedence, order independence, known-finalizer acceptance, and unknown-finalizer rejection. The governed `local-2-1-corrundum-maxcap-13` campaign machine-checks one exact repair record, nine cap-13 runtime bindings, and the absence of maximum-level conflicts on Factorio `2.1.14` with exact `PlanetsLib_1.19.5` and `corrundum_1.0.47` archives.

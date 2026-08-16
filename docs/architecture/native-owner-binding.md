---
title: "Native Owner Binding"
status: current
applies_to: "3.1.9+"
audience: maintainer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-20
supersedes: []
superseded_by: []
---

# Native Owner Binding

A stream with a recognized infinite technology owned by Factorio or another mod remains one configurable MIR stream. Generated, adopted, already-covered, and fallback outcomes all use the same stable `ips-*` setting IDs; the owner that happens to provide coverage does not create a second settings contract.

## Declarative Contract

`prototypes/streams/productivity.lua` may declare a `native_owner_binding` with one owner technology, an effect-product scope, eligibility requirements, recognized cost formulas, default preservation, and fallback policy. The declaration is data only. Compatibility overlays cannot configure or mutate the owner.

The Factorio 2.1 bindings are processing units to `processing-unit-productivity`, plastic to `plastic-bar-productivity`, low-density structures to `low-density-structure-productivity`, rocket fuel to `rocket-fuel-productivity`, and steel plate to `steel-plate-productivity`. Their reviewed source values and source-file digest live in `.mir/native-owner-cost-models.json`.

## Planning

`prototypes/mir/planner/native_owner_binding.lua` reads final prototype facts and effective startup settings, then produces exactly one explicit operation: `preserve_native_owner`, `configure_native_owner`, `adopt_native_owner_effects`, or `configure_and_adopt_native_owner`. A fully covered owner still produces a binding row, so absence of a new recipe effect never hides settings ownership or configuration intent.

Default setting values preserve the complete final owner snapshot, even when the final owner values differ from MIR's generated-stream catalog defaults. Disabling the stream stops before owner planning and leaves the external owner untouched. Explicit non-default settings may configure recognized cost, research time, maximum level, and relevant effect values. Unrelated effects, prerequisites, science ingredients, and other owner fields remain unchanged.

The cost adapter preserves either Factorio's `growth^L*base` formula style, MIR's `base*growth^(L-1)` style, or a fixed numeric count. An unrecognized external formula is safe only while cost settings stay at their defaults. An explicit base or growth override on an unrecognized formula rejects the binding instead of guessing.

## Transaction And Fallback

Planning records immutable input and expected output snapshots plus fingerprints. Whole-plan validation rejects duplicate owner bindings. The emission transaction verifies the input fingerprint immediately before applying one prevalidated owner update, and output validation verifies the resulting fingerprint. The default preserve operation performs no assignment, retaining exact table identity and final external balance.

The emitted schema-3 binding artifact carries compact, versioned input and output research-cost descriptors with separate semantic, provenance-bound authority, and qualification identities. On a configuration change, Factorio normalizes the active fraction to preserve completed unit-equivalent work as `old fraction × old realized cost ÷ new realized cost`, clamped to `[0,1]`, before MIR's handler runs. Runtime state compares binding identities and may evaluate exact descriptors for diagnostics, but it does not reparse formula strings or mutate the already-normalized fraction. This preserves the player's level, current research selection, queue, and completed work without a redundant second conversion. Missing, malformed, digest-mismatched, or over-budget descriptors are logged without changing progress.

If the owner is absent, finite, unreachable, malformed, or unsafe to configure, eligible recipes fall back to MIR generation. Recipes already covered by an existing owner are excluded from fallback generation so MIR never creates duplicate productivity coverage. Only emission code may apply the planned transaction or create the fallback technology.

## Evidence

The native-owner settings matrix covers defaults, disabled streams, each individual setting, combined settings, relevant-effects-only behavior, unrelated-effect preservation, fully covered owners, recognized and unrecognized formulas, transaction fingerprints, duplicate bindings, settings profiles, configuration-change resets, current research selection, the complete fixed/linear/exponential/hybrid sixteen-row transition matrix, completed-work preservation, and fail-closed malformed/over-budget descriptors. Target-specific runtime evidence remains mandatory for every backport line.

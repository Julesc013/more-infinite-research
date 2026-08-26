---
title: "StreamSpec Schema"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-25
supersedes: []
superseded_by: []
source_of_truth_for:
  - stream-spec-schema
---

# StreamSpec Schema

A `StreamSpec` is the validated contract a planner hands to emission code before MIR creates or mutates generated technology prototypes.

Required fields:

| Field | Meaning |
| --- | --- |
| `schema` | Schema version. |
| `manifest_id` | Stable generated stream manifest key. |
| `stream_key` | Internal stream key. |
| `technology_name` | Factorio prototype name to create or update. |
| `effects` | Validated technology effects. |
| `science` | Lab-compatible ingredient set. |
| `prerequisites` | Validated prerequisite list. |
| `migration_policy` | Stable, pending migration, or unreleased. |

Before planning produces a `StreamSpec`, every raw declaration is normalized into a schema-1 canonical descriptor:

| Descriptor field | Meaning |
| --- | --- |
| `schema` | Canonical descriptor schema version. |
| `id` | Stable raw stream key. |
| `kind` | `recipe-productivity` or `direct-effect`. |
| `effect` | Typed field, unit, display multiplier, canonical anchor, integer policy, and runtime-delta policy. |
| `targets` | Positive feature requirements plus required mods, prototypes, technologies, and effect types. |
| `technology_risk` | Optional schema-1 classification for a technology whose researched effect may disrupt existing factories, blueprints, or save behavior. This is independent of default enablement. |

Raw recipe-productivity declarations may also carry `productivity_permission_recipes`. Each row names one exact recipe and a non-empty set of required active mods. The phase-12 permission command runs before recipe facts are captured and sets `allow_productivity = true` only when that exact recipe exists and every declared mod is active. This is an explicit engine-eligibility grant, not a pattern match: it must not be used for recovery, recycling, or ambiguous third-party recipe families.

The canonical registry is private. Consumers use `snapshot()` or `get()` and receive deep copies. Duplicate raw IDs, overlay attempts to create unknown declarations, and overlay attempts to inject canonical descriptors are errors. Numeric defaults use the largest compatible positive declared anchor, making them invariant under array ordering while preserving the 3.0.5 primary-tier values.

`technology_risk` contains a governed `class`, stable `reason`, localized tooltip note, and settings attention rank. `factory-disruptive` technologies remain in the first generated-technology settings bucket even when their enable checkbox defaults on. The settings builder and compiler consume the same classification: the former orders and warns, while the latter carries the classification into the generation record and appends the warning to the emitted technology description. A missing technology-specific note falls back to the class warning, and a description that already embeds the selected locale key is not decorated twice. Risk classification must never be inferred from an enable checkbox.

## Transition Adapter

Raw declarations are first normalized through `prototypes/mir/domain/streams/descriptor.lua`. Planned technologies then pass through `prototypes/mir/emit/stream_spec_adapter.lua` and `prototypes/mir/domain/streams/stream_spec.lua` before they enter `prototypes/mir/emit/technology_builder.lua`. The adapter preserves existing technology names, effects, science ingredients, prerequisites, cost formula, research time, max level, and order while keeping the actual `data:extend` call behind the emit layer.

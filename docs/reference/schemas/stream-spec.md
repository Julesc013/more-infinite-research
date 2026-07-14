---
title: "StreamSpec Schema"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
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

The canonical registry is private. Consumers use `snapshot()` or `get()` and receive deep copies. Duplicate raw IDs, overlay attempts to create unknown declarations, and overlay attempts to inject canonical descriptors are errors. Numeric defaults use the largest compatible positive declared anchor, making them invariant under array ordering while preserving the 3.0.5 primary-tier values.

## Transition Adapter

Raw declarations are first normalized through `prototypes/mir/domain/streams/descriptor.lua`. Planned technologies then pass through `prototypes/mir/emit/stream_spec_adapter.lua` and `prototypes/mir/domain/streams/stream_spec.lua` before they enter `prototypes/mir/emit/technology_builder.lua`. The adapter preserves existing technology names, effects, science ingredients, prerequisites, cost formula, research time, max level, and order while keeping the actual `data:extend` call behind the emit layer.

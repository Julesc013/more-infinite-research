---
title: "ADR 0019: TargetProfileV2"
status: current
applies_to: "3.1.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# ADR 0019: TargetProfileV2

## Decision

`.mir/targets.json` schema 2 is the target capability authority. Every profile declares positive prototype shapes, runtime state, available emitters, asset policy, expected stream count, feature capabilities, and required validation groups. The checked-in Lua view is generated deterministically from that manifest.

Compiler rules and fixtures consume capabilities and shapes, not Factorio-version branches. A target declaration unsupported by the selected profile fails closed. Every profile is positive-only: absent features, mod namespaces, effect types, emitters, or prototype shapes are unsupported. Negative stream, mod, effect, and setting lists are rejected by validation.

## Consequences

- Target-specific source forks are adapters rather than separate compiler implementations.
- Cross-target fixtures derive science-pack kind and stream count from the profile.
- Every Factorio line is positive-only for required mods and technology effects; reduced and planned profiles use empty allowlists where no target proof exists.
- The 0.16 and 0.15 profile shapes are plans, not support claims, until matching binary evidence passes.

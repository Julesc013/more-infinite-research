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

Compiler rules and fixtures consume capabilities and shapes, not Factorio-version branches. A target declaration unsupported by the selected profile fails closed. Historical reduced profiles may retain transitional negative compatibility fields until their independent binary refresh, but new behavior may not depend on those fields.

## Consequences

- Target-specific source forks are adapters rather than separate compiler implementations.
- Cross-target fixtures derive science-pack kind and stream count from the profile.
- Factorio 2.1 and 2.0 remain positive-only for required mods and technology effects.
- The 0.16 and 0.15 profile shapes are plans, not support claims, until matching binary evidence passes.

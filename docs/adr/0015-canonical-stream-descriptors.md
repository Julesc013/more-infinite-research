---
title: "ADR-0015: Canonical Stream Descriptors"
status: current
applies_to: "3.1.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# ADR-0015: Canonical Stream Descriptors

## Decision

MIR normalizes every raw stream declaration exactly once into a schema-1 descriptor containing stable identity, kind, typed effect metadata, positive target requirements, and the stable settings sort label. The registry keeps canonical descriptors private and returns deep copies. Settings and planners consume the same normalized contract.

Duplicate stream IDs, unknown stream creation by compatibility profiles, and descriptor injection by overlays fail closed. Numeric effect defaults use the largest compatible positive declared anchor rather than array position. Explicit scripted-effect anchors remain authoritative.

## Consequences

- Reordering effect arrays or productivity groups cannot change startup defaults.
- Settings and emission share one effect contract.
- The settings stage no longer owns a parallel stream-name ordering table.
- Compatibility profiles can extend known raw selectors but cannot bypass normalization.
- Consumers may transform their copies without mutating later compiler phases.
- Generated IDs and 3.0.5 setting defaults remain unchanged.

## Evidence

`fixtures/assert-generation-integrity` validates all 70 descriptors, order invariance, copy isolation, duplicate rejection, and overlay injection rejection on a real Factorio load.

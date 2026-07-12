---
title: "ADR 0018: Automatic Generated ID Policy"
status: current
applies_to: "3.1.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# ADR 0018: Automatic Generated ID Policy

## Decision

Automatic technology IDs derive from stable semantic family IDs and a fixed schema, never from mod IDs, recipe IDs, prototype discovery order, or scenario order. A new family ID must be predeclared at settings stage, registered in both stream manifests, added to the reviewed automatic-family golden, and covered by positive and negative fixtures before emission is enabled.

The first reviewed IDs are:

- `mir-auto-prod-manufacturing-assembling-machine-1`;
- `mir-auto-prod-manufacturing-lab-1`.

Existing 3.1.0 IDs remain in the immutable released-ID golden. New family IDs use a separate 3.1.0 golden so adding a reviewed identity cannot obscure loss or renaming of a released identity.

## Consequences

- The default `safe-attach` mode creates no new automatic-family technologies.
- `safe-generate` and exact-pack modes may emit only predeclared family IDs.
- One technology per discovered recipe is forbidden.
- Future sharding must use a fixed predeclared shard set and deterministic subject assignment.

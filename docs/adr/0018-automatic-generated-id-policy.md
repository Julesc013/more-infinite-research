---
title: "ADR 0018: Automatic Generated ID Policy"
status: current
applies_to: "3.2.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: []
superseded_by: []
---

# ADR 0018: Automatic Generated ID Policy

## Decision

Automatic technology IDs derive from stable semantic family IDs and a fixed schema, never from mod IDs, recipe IDs, prototype discovery order, or scenario order. A new family ID must be predeclared at settings stage, registered in both stream manifests, added to the automatic-family golden, assigned an explicit creation maturity, and covered by positive and negative fixtures before emission is enabled.

The first predeclared experimental IDs are:

- `mir-auto-prod-manufacturing-assembling-machine-1`;
- `mir-auto-prod-manufacturing-lab-1`.

Existing 3.1.0 IDs remain in the immutable released-ID golden. New family IDs use a separate golden so adding an identity cannot obscure loss or renaming of a released identity. A stable ID does not imply that its balance or creation policy is reviewed.

## Consequences

- The default Apply safe changes action creates no new automatic-family technologies because `Allow new research creation` defaults off.
- Creation may emit only registered, predeclared family IDs with declared maturity.
- Reviewed-data mode rejects experimental families even when a compatibility pack requests generation. The broad opt-in lane can still expose them when research creation is enabled and the reviewed-data requirement is disabled.
- One technology per discovered recipe is forbidden.
- Future sharding must use a fixed predeclared shard set and deterministic subject assignment.
- Player controls remain generic when families are added; technology-specific choices belong to manifests and family modules, not new compiler modes.

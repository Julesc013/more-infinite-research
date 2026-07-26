---
title: "MIR 3.2.1 Release Notes"
status: current
applies_to: "3.2.1"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-26
supersedes: []
superseded_by: []
---

# MIR 3.2.1

MIR 3.2.1 is an emergency Space Age progression hotfix for MIR 3.2.0.

## Fixed

- Preserved researched Space Age planets and starmap connections.
- Restored normal platform travel to previously discovered planets.
- Corrected `unlock-space-location` validation so it recognizes both abstract `space-location` prototypes and concrete `planet` prototypes.
- Retained the existing fail-closed sanitation behavior for genuinely missing recipe, item, quality, entity, ammunition, and location targets.
- Did not reintroduce global force-wide technology-effect resetting.

## Cause

Factorio stores concrete planets such as Vulcanus, Gleba, Fulgora, and Aquilo under the `planet` prototype type. Planets are valid space locations, but MIR 3.2.0's generic target inventory searched only the separate `space-location` prototype bucket. It therefore removed valid planet-discovery effects as though the targets did not exist.

This left the surfaces intact while the normal starmap, space connections, and platform schedules treated those planets as undiscovered.

## Upgrade behavior

Install 3.2.1 over 3.2.0 and load the affected save. The corrected technology prototypes retain their valid discovery effects. Do not continue using 3.2.0 on an affected Space Age save.

## Qualification status

The emergency distribution is built deterministically with a focused source-contract regression. Complete candidate-bound runtime and release qualification continues after the emergency package is available.

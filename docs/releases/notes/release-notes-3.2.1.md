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

## Release artifact

- Package: `dist/more-infinite-research_3.2.1.zip`
- Package source: `f3f8cabd0f84be674d5cc190343a9b7df5ba65c5`
- Size: `1,029,716` bytes
- Entries: `290`
- SHA-256: `4CE24BE8550CB76EADC2B076747277025E9FD3E7BAAE3E4A996EDD36F78005A6`
- Compatibility: Factorio `2.1.8` or newer

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

The exact artifact above is recorded and ready for the `3.2.1` tag. Its focused emergency source-contract regression passed. Broader branch and candidate validation is still in progress and is not represented as complete.

Tag and publish this exact ZIP without rebuilding it.

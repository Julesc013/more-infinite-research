---
title: "MIR 2.4.1 Release Notes"
status: current
applies_to: "2.4.1"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-14
supersedes: []
superseded_by: []
---

# MIR 2.4.1 Release Notes

MIR 2.4.1 is a Factorio 2.0 startup-safety patch based on the published 2.4.0 release.

## Fixed

- Generated research no longer inherits the disabled vanilla Automation science technology when another mod leaves the Automation science pack recipe initially available.
- Finite extension anchors and other prerequisite candidates remain excluded when their technology path transitively reaches a disabled technology.
- The exact configuration now has a dedicated Factorio 2.0 runtime regression so future releases cannot silently restore the fatal graph edge.

Generated technology IDs, setting IDs, defaults, runtime state, and the supported Factorio 2.0 feature surface remain unchanged from 2.4.0.

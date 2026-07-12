---
title: "MIR 2.5.0 Release Notes"
status: current
applies_to: "2.5.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: []
superseded_by: []
---
# MIR 2.5.0

MIR 2.5.0 is the unpublished Factorio 2.0 semantic companion to the automatic compiler line. It preserves the published 2.4.0 IDs and save-facing contracts while carrying only target-supported behavior.

## Compatibility hotfix

- Detects the exact cross-mod topology where Astroponics requires Space Science while Muluna's Space Science chain reaches Astroponics.
- Removes only the circular `astroponics -> space-science-pack` prerequisite when both named mods and both path directions prove the conflict.
- Leaves unrelated external cycles fatal and keeps all MIR-generated cycles, missing prerequisites, and disabled prerequisites fatal.
- Uses iterative graph traversal so large modded technology graphs do not overflow Lua's call stack.

The repair is narrowly topology-gated. It does not broadly rewrite another mod's technology graph and it does not claim feature parity with the Factorio 2.1 release.

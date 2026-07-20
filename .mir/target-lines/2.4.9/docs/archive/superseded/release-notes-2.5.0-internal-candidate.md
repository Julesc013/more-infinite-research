---
title: "MIR 2.5.0 Release Notes"
status: archived
applies_to: "2.5.0"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: []
superseded_by:
  - docs/releases/notes/release-notes-2.4.0.md
---
# MIR 2.5.0

MIR 2.5.0 was an unpublished internal Factorio 2.0 candidate. Its applicable fixes were folded into MIR 2.4.0; this page is retained only as superseded evidence.

## Compatibility hotfix

- Detects the exact cross-mod topology where Astroponics requires Space Science while Muluna's Space Science chain reaches Astroponics.
- Removes only the circular `astroponics -> space-science-pack` prerequisite when both named mods and both path directions prove the conflict.
- Leaves unrelated external cycles fatal and keeps all MIR-generated cycles, missing prerequisites, and disabled prerequisites fatal.
- Uses iterative graph traversal so large modded technology graphs do not overflow Lua's call stack.

The repair is narrowly topology-gated. It does not broadly rewrite another mod's technology graph and it does not claim feature parity with the Factorio 2.1 release.

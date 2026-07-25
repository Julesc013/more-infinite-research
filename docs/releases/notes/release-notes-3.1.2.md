---
title: "MIR 3.1.2 Release Notes"
status: current
applies_to: "3.1.2"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: []
superseded_by: []
---

# MIR 3.1.2 Release Notes

MIR 3.1.2 is an emergency Factorio 2.1 compatibility hotfix for a technology prerequisite cycle observed in large Space Age modpacks containing Muluna and Astroponics.

## Hotfix

Muluna can make `space-science-pack` depend on a progression chain that reaches `astroponics`, while Astroponics normally requires `space-science-pack`. Together those edges close a cycle that Factorio rejects while loading technology prototypes. MIR now applies one topology-gated repair when both named mods are active and the mutual path is proven: it removes only `astroponics -> space-science-pack` and preserves Astroponics' other prerequisites.

The repair does not broadly rewrite technology graphs. It stays inactive when either mod is absent or when the reverse path no longer exists. Cycles containing an MIR-generated technology, missing prerequisites, and disabled prerequisites remain hard errors. The final graph walk is iterative so unusually deep modded technology trees do not risk a Lua recursion overflow.

## Upgrade

Update normally from MIR 3.1.1. No settings reset is required. Setting keys, automatic coverage modes, stored values, technology IDs, research levels, and runtime state contracts are unchanged.

This source is the hotfix anchor for the untagged descending compatibility-port RCs. Each older Factorio line receives only its target-supported subset and must pass its matching binary and package checks before release.

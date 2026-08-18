---
title: "MIR 4.0 Publication Copy"
status: current
applies_to: "MIR 4.0.0 candidate programme"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-18
supersedes: []
superseded_by: []
---

# MIR 4.0 Publication Copy

This is prepared copy, not publication authority. Replace candidate status and target rows only from the final sealed qualification record.

## GitHub release summary

More Infinite Research 4.0 preserves the proven MIR 3 player behavior while introducing target-specific distributions and a separate developer-preview platform. Download only the player ZIP matching your Factorio line. Modders can separately download API/SDK V0, MEP V0, the reference extension, and Inspector previews; these assets are read-only, package-excluded, and may change before 1.0.

The final release table must list each admitted target's Factorio line, direct predecessor, archive name, SHA-256, qualification status, and support tier. Private or deferred targets must not appear as downloadable public player products.

## Mod Portal description template

More Infinite Research extends selected finite technologies into governed infinite research streams while preserving target-local compatibility behavior. MIR 4.0 uses an independently built distribution for this Factorio line and supports direct upgrade from the predecessor named in the release table.

Before upgrading, back up your save and mod directory. Install only the archive matching your Factorio version, remove the predecessor archive, load the save, verify settings and active research, save, and reload twice. Report problems with the exact Factorio and MIR versions, mod list, startup settings, save or minimal reproduction, and support snapshot when available.

Developer SDKs, schemas, fixtures, evidence, governance records, and Inspector are GitHub assets. They are intentionally excluded from Mod Portal player packages.

## Target suffix

Append exactly one qualified target statement:

- f210: `For Factorio 2.1. Direct upgrade predecessor: MIR 3.2.11.`
- f200: `For Factorio 2.0. Direct upgrade predecessor: MIR 2.5.11.`
- f110: `For Factorio 1.1. Direct upgrade predecessor: MIR 1.9.9.`
- f100: `For Factorio 1.0. Direct upgrade predecessor: MIR 1.8.9.`

Do not prepare a public historical suffix unless that target has its own admission, qualification, seal, and publication decision.

## Player FAQ

### Why are there several 4.0 versions?

`4.0.0` is the source release. A distribution such as `4.0.21000` identifies the Factorio target and prevents capabilities or omissions from silently leaking between engine generations.

### Will my MIR 3 research survive?

The matching target preserves IDs, settings, migrations, research and state from its named terminal predecessor. The final release is published only after direct-upgrade and repeated-reload evidence passes.

### Does automatic mod support rewrite unknown mods?

No. Existing certified behavior may apply automatically. New or opaque semantics are preserved, diagnosed, referred to an extension or review, omitted with evidence, or rejected by hard safety. Diagnose-only synthesis cannot mutate the player package.

### Do players install the SDK or Inspector?

No. Player ZIPs are self-contained Factorio mods. Developer-preview assets are separate GitHub downloads for modders, tool authors, and maintainers.

### Which package should I download?

Use only the package whose target row matches the exact Factorio line shown by the game. Never rename or retarget another distribution.

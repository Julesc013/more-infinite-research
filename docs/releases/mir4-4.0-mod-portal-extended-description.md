---
title: "MIR 4.0 Mod Portal Extended Description"
status: current
applies_to: "MIR 4.0.0"
audience: player
doc_type: release-note
owner: mir-maintainers
last_reviewed: 2026-08-30
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-4.0-mod-portal-extended-description-copy
---

# More Infinite Research

*Trickle-down economics bring productivity gains to all industries.*

More Infinite Research adds configurable productivity and bonus research for intermediates, science packs, infrastructure, logistics, combat, player bonuses, robots, and supported Space Age systems.

MIR discovers the active technology, recipe, item, fluid, science-pack, and laboratory environment late in the prototype stage. It creates or adopts research only when ownership, target capability, progression, and safety checks permit it. Unsupported or ambiguous subjects are preserved, omitted, or reported instead of being forced into an invalid technology tree.

## Choose the correct download

MIR 4 uses one source release and target-specific package versions:

| Factorio line | Package pattern | MIR 4.0 package |
| --- | --- | --- |
| 2.1 | `4.MINOR.210PP` | `4.0.21000` |
| 2.0 | `4.MINOR.200PP` | `4.0.20000` |
| 1.1 | `4.MINOR.110PP` | `4.0.11000` |
| 1.0 | `4.MINOR.100PP` | `4.0.10000` |

`PP` is the shared source patch. Distribution versions for different targets are not a simple higher-is-newer sequence. Select the package matching the running Factorio line.

## Main features

- Configurable recipe and fluid productivity research.
- Infinite or bounded continuations for supported technologies.
- Direct bonuses for logistics, weapons, robots, laboratory research, player attributes, and Space Age cargo systems where supported.
- Per-family enablement, cost, growth, maximum level, research time, effect scaling, science policy, and compatibility controls.
- Target-aware science-pack and laboratory reachability.
- Stable generated technology identities and upgrade-preserving migrations.
- Safe external-owner adoption and duplicate-effect prevention.
- Explicit diagnostics for skipped, preserved, conflicting, or unsupported behavior.

F210 and F200 are the full maintained targets where their features are representable. F110 and F100 are reduced LTS targets with explicit omissions. Compatibility is qualified against exact Factorio versions, mod archives, settings, load order, and evidence; MIR does not claim automatic perfection for every arbitrary modpack.

## Upgrading

1. Back up the save and current mod directory.
2. Install the package matching the Factorio line and remove the predecessor ZIP.
3. Keep startup settings unchanged for the first load.
4. Upgrade directly from MIR 3.2.11 on Factorio 2.1, MIR 2.5.11 on Factorio 2.0, MIR 1.9.9 on Factorio 1.1, or MIR 1.8.9 on Factorio 1.0.
5. Save after migration and configuration changes, then reload the upgraded save twice.

## Frequently asked questions

### Which MIR version should I install?

Use Factorio 2.1 → `4.0.21000`, Factorio 2.0 → `4.0.20000`, Factorio 1.1 → `4.0.11000`, or Factorio 1.0 → `4.0.10000`. Never install an API, SDK, MEP, reference-extension, or Inspector preview archive as a Factorio mod.

### What do MIR 4 version numbers mean?

MIR has a shared source version and a target distribution version. For source `4.6.8`, the target packages are `4.6.21008`, `4.6.20008`, `4.6.11008`, and `4.6.10008`. Compare source versions within one target; a package for another target is not newer merely because an encoded component is numerically larger.

### Does MIR support every mod or modpack?

No blanket claim is made. MIR provides structural compatibility and exact evidence-backed profiles, but does not guess arbitrary hidden Lua behavior. It can apply certified behavior, preserve an existing owner, request an extension or review, omit an unsupported target surface, or report a hard-safety failure.

### Why was a technology skipped or preserved?

Typical reasons include another valid owner, an unavailable target effect, unreachable science, a missing or cyclic prerequisite, a recycling or recovery process family, or custom semantics requiring an extension or review. Check MIR diagnostics or export a support bundle.

### Can I change costs, effects, or maximum levels?

Yes. MIR exposes target-appropriate startup settings for research families, costs, growth, time, effect scaling, science policy, and maximum levels. Unsupported settings are omitted or hidden on reduced targets rather than presented as inert controls.

### Can mod developers add first-party MIR support?

Yes. The separate developer preview includes the data-only MIR Extension Protocol, schemas, templates, SDK bindings, environment locks, diagnostics, and conformance tools. Extensions cannot bypass hard safety or mutate player prototypes directly.

### How do I report an issue?

Open a Mod Portal discussion or GitHub issue with the Factorio version, MIR package version, exact mod list and startup settings, `factorio-current.log`, a save or minimal reproducer, and the MIR support bundle when available. Never include passwords, API tokens, signing material, or unrelated private files.

Developer previews are separate GitHub downloads, not installable player mods.


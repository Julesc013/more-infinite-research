---
title: "MIR 3.1.1 Release Notes"
status: current
applies_to: "3.1.1"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: ["release-notes-3.1.0.md"]
superseded_by: []
---

# MIR 3.1.1 Release Notes

MIR 3.1.1 is the release-ready Factorio 2.1 automatic compatibility compiler. It supersedes the unpublished 3.1.0 candidate after a startup crash was found with a multi-output Space Age Galore recipe.

## Hotfix

- Multiple MIR streams may legitimately recognize the same multi-output recipe. The compiler now assigns each overlapping recipe effect to one deterministic owner before prototype emission.
- Existing compatible productivity research wins over a newly generated claim. Fixed streams win over generic generated families, and stable stream identity breaks remaining ties.
- A stream that loses only its overlapping effects becomes an auditable non-materializing decision. A partially overlapping stream retains every unique effect.
- The final duplicate-effect assertion remains active and still rejects malformed duplicates within a single stream or any duplicate that bypasses arbitration.
- The regression scenario reproduces `vgal-coal-crushing` as a coal, carbon, and sulfur multi-output recipe and requires exactly one generated owner.

## Upgrade

Update normally from MIR 3.0.5 or an unreleased 3.1.0 test build. Do not reset mod settings. The hotfix changes generation ownership only; setting keys, stored option values, technology IDs, research levels, and runtime state contracts remain unchanged.

MIR 3.1.1 is the modern source anchor for the descending Factorio compatibility-port campaign. Every target line still requires its own API cuts, package, matching binary load, and evidence; this release does not imply feature parity on older Factorio versions.

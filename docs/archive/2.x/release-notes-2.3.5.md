---
title: "More Infinite Research 2.3.5 Release Notes"
status: archived
applies_to: "2.0"
audience: player
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-11
supersedes: [docs/archive/2.x/release-notes-2.3.0.md]
superseded_by: [../../releases/README.md]
---
# More Infinite Research 2.3.5 Release Notes

`2.3.5` is the Factorio `2.0` semantic backport of the MIR 3.0.5 settings
and compatibility work. Generated technology IDs and existing defaults remain
stable.

## New settings

- `mir-productivity-cap-self-recycling-only` optionally limits selected
  productivity caps above +300% to proven non-generative single-item
  self-recycling recipes. Unsafe recipes retain their existing cap.
- `mir-unrestricted-modules` optionally opens all five module effect types and
  discovered module categories on existing recipe and receiver slots. It does
  not add slots or mutate module prototypes.
- Each non-scripted generated technology exposes an effect-per-level setting.
  Changing its anchor scales related tiers proportionally; adopted external
  owner values are not rewritten.

The settings are startup-only and require a restart. They are opt-in and can
substantially change factory balance.

## Validation boundary

The same static, package, Factorio 2.0 base, Space Age, settings-profile, and
compatibility fixture gates used by the existing 2.3.5 candidate remain
required before publication. This note does not claim runtime validation until
the Factorio 2.0 binary gate is rerun for the new settings matrix.

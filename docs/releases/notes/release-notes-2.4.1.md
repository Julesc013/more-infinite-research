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

MIR 2.4.1 is the complete Factorio 2.0 projection of the sealed MIR 3.1.9 portable behavior set, with 2.4.0 retained as its save-upgrade predecessor.

## Fixed

- Generated research no longer inherits the disabled vanilla Automation science technology when another mod leaves the Automation science pack recipe initially available.
- Finite extension anchors and other prerequisite candidates remain excluded when their technology path transitively reaches a disabled technology.
- The exact configuration now has a dedicated Factorio 2.0 runtime regression so future releases cannot silently restore the fatal graph edge.
- The normal stream settings now configure recognized existing Space Age infinite productivity owners, including plastic and low density structures.
- Cost base and growth now apply as one displayed pair when either is customized.
- Native-owner level, current research selection, and fractional progress survive startup-cost changes and upgrades from 2.4.0.
- Default settings preserve native or modded balance, disabled streams leave owners untouched, unknown formulas reject explicit cost changes, and unsafe adoption falls back to MIR generation.
- Native-owner updates retain immutable input/output fingerprints and whole-plan duplicate-owner rejection.

Generated technology IDs, setting IDs, defaults, and runtime namespaces remain compatible with 2.4.0. Factorio 2.1-only cargo effects and metadata remain excluded by the 2.0 target profile.

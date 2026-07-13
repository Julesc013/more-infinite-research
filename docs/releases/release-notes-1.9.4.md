---
title: "MIR 1.9.4 Candidate Notes"
status: current
applies_to: "1.9.4"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-14
supersedes: []
superseded_by: []
---

# MIR 1.9.4 Candidate Notes

MIR 1.9.4 is a maintenance candidate for Factorio 1.1. It preserves the intentionally reduced 1.9.3 feature set while hardening generated research prerequisites and compatibility ownership.

- Generated technology prerequisites now use one researchability authority and avoid disabled, cyclic, self-locked, or unrecognized science paths.
- Technology-graph validation now uses an iterative traversal, preserving strict cycle rejection without risking a Lua call-stack overflow on unusually deep modded prerequisite chains.
- Weapon-speed overlap cleanup is restricted to MIR-generated continuations, preserving external infinite technologies.
- New target-era fixtures run on the real Factorio 1.1.110 binary.
- Release archives are now byte-deterministic and qualified as exact binaries before an immutable candidate seal is created.
- Settings for unsupported recipe-productivity research are no longer displayed as controls that Factorio 1.1 cannot apply.

This RC does not add Factorio 2.x recipe-productivity, Space Age, cargo, prototype-limit, recycler, module-permission, or settings-profile features. In particular, Factorio 1.1 has no `change-recipe-productivity` technology effect, so low density structure, plastic, processing unit, rocket fuel, and other recipe-productivity families are intentionally classified as omitted by capability rather than simulated.


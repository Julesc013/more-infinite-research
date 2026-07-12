---
title: "MIR 1.8.2 Candidate Notes"
status: current
applies_to: "1.8.2"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# MIR 1.8.2 Candidate Notes

MIR 1.8.2 is a maintenance candidate for Factorio 1.0. It preserves the intentionally reduced 1.8.1 feature set while hardening generated research prerequisites and compatibility ownership.

- Generated technology prerequisites avoid disabled, cyclic, self-locked, or unrecognized science paths.
- Weapon-speed overlap cleanup is restricted to MIR-generated continuations, preserving external infinite technologies.
- Target-era science packs and the `tanks` technology remain authoritative.

This RC does not add features from newer Factorio engines.


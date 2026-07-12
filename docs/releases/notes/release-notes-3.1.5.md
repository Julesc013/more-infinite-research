---
title: "MIR 3.1.5 Candidate Notes"
status: current
applies_to: "3.1.5"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: []
superseded_by: []
---

# MIR 3.1.5 Candidate Notes

MIR 3.1.5 is the post-backport Factorio 2.1 development candidate. It keeps the 3.1.2 Muluna/Astroponics cycle repair and folds portable correctness and validation lessons back into the modern compiler.

## Changes

- Compiled generation plans are published only after authoritative plan validation.
- Selected configuration-change scenarios execute their actual load phase.
- Settings override fixtures target the selected Factorio version instead of assuming the current line.
- Generated count formulas use compact parser-compatible syntax without changing their mathematical cost curves.
- The complete Factorio 2.0 through 0.13 candidate wave is recorded in governance and release documentation.

No target-specific metadata, science-pack substitutions, finite-research emulation, or effect cuts were returned to the Factorio 2.1 implementation.

This is an untagged, unreleased development candidate.

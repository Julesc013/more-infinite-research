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
- Automatic recipe support now separates action, research creation, and reviewed-data requirements into short, generic controls with explicit defaults, sentence-case options, consistent widths, and outcome-first tooltips.
- “Apply safe changes” no longer carries a long recommendation suffix; the two checkbox names state the behavior they authorize.
- Compiler policy is a pure schema-2 contract that registered family modules can reuse without adding mod-, recipe-, technology-, or version-specific settings.
- Built-in automatic families now use a sorted, data-only CompilerProvider schema with stable diagnostics, migration metadata, validation hooks, and planning-only emission adapters.
- Assembling-machine and lab manufacturing creation remains experimental: reviewed-data mode skips both, while the explicit broad opt-in lane retains them for testing ahead of the 3.2.0 compiler work.
- Hid the two experimental automatic-family tuning groups until review, without deleting their stable settings or broad opt-in generation path.
- Hid Space Age-only technology setting groups in base-only configurations; they reappear with preserved values when the DLC is active.
- Existing profiles keep working through the hidden legacy setting bridge; explicit new controls take precedence.
- Hard target, ownership, productivity, recycling, stochastic-output, catalyst, science, lab, prerequisite, identity, and cycle gates remain non-overridable.
- The complete Factorio 2.0 through 0.13 candidate wave is recorded in governance and release documentation.

No target-specific metadata, science-pack substitutions, finite-research emulation, or effect cuts were returned to the Factorio 2.1 implementation.

Automated qualification passed 91/91 target scenarios, both exact upgrade anchors, and 9/9 available ecosystem loads. This is an untagged, unreleased candidate awaiting identity-bound interactive review.

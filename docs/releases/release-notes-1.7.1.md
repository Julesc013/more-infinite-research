---
title: "MIR 1.7.1 Candidate Notes"
status: current
applies_to: "1.7.1"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: []
superseded_by: []
---

# MIR 1.7.1 Candidate Notes

MIR 1.7.1 is an unreleased Factorio 0.17 safety backport. It keeps the reduced native-infinite feature set from 1.7.0.

- MIR now validates every generated technology's complete reachable prerequisite graph.
- The validator rejects missing, disabled, or cyclic prerequisite paths with a deterministic diagnostic.
- The graph walk is iterative, so unusually deep modded technology trees cannot exhaust the Lua call stack during MIR validation.

The Space Age-specific Muluna and Astroponics repair is intentionally absent because those technologies do not exist on Factorio 0.17.

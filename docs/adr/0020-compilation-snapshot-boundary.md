---
title: "ADR 0020: Compilation Snapshot Boundary"
status: current
applies_to: "3.2.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---

# ADR 0020: Compilation Snapshot Boundary

## Decision

The compiler core accepts only `CompilationSnapshot` schema 1 and `PolicySnapshot` schema 1 through `planner/compiler.lua:compile(snapshot, policy)`. Factorio globals, settings, loaded mods, logging, clocks, telemetry, and active context are adapter concerns and are forbidden below that API.

`CompilationSnapshot` binds normalized prototype surfaces, relationship and recipe facts, graph input, effect-target inventory, stream proposals, base-continuation proposals, and their fingerprints. `PolicySnapshot` binds effective settings, compatibility policy, streams, promotion authority, hard gates, effect contracts, quality profiles, and transformation policy.

## Consequences

Pure compilation can be serialized, replayed in a fresh process, permuted, tampered with, and compared without Factorio. Any new ambient read below the boundary is an architecture-test failure.

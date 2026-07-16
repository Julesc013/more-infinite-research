---
title: "MIR 3.2.0 Release Notes"
status: current
applies_to: "3.2.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-17
supersedes: []
superseded_by: []
---

# MIR 3.2.0 Release Notes

MIR 3.2.0 is a release-engineering overhaul built from the MIR 3.1.9 line plus the portable target-capability guard accumulated on `dev`. It introduces persistent content-addressed test evidence so unchanged scenarios can reuse exact prior proof while changed package, gameplay, settings, migration, fixture, harness, binary, and dependency inputs rerun the lanes they affect.

The release keeps the public setting IDs, generated technology IDs, migrations, and runtime-state namespaces from MIR 3.1.9. The explicit capability guard leaves Factorio 2.1 mod-data emission enabled but changes packaged data-stage source, so the 3.2.0 candidate requires fresh gameplay qualification rather than borrowing the 3.1.9 matrix. Version-only and package-only changes in later candidates still receive fresh deterministic-build, exact-ZIP load, and upgrade proof; gameplay scenarios are reused only when their declared effective domains are byte-identical.

Release qualification now produces one reviewable verification plan, stable per-scenario fingerprints, trusted evidence capsules, and one aggregate gate. Factorio 2.0 backports calculate independent target-specific fingerprints and cannot borrow Factorio 2.1 evidence.

The 3.2.0 candidate also fixes a Space Exploration plus Krastorio 2 startup crash caused by Space Exploration removing `kr-copper-cable-from-copper-ore` after MIR had emitted a copper-cable productivity effect for it. Space Exploration is a hidden optional ordering dependency, and MIR now uses one target-aware effect-contract authority to remove impossible known recipe references from both generated and external technology effects before final assertions. The regression covers both recipe-productivity and `unlock-recipe` targets while retaining valid effects. This is startup-integrity evidence, not a broad Space Exploration compatibility claim.

Compiler safety now validates the combined existing-plus-planned technology graph with an iterative strongly connected component pass before emission, replaces whole-prototype base continuation cloning with an allowlisted builder, moves stream mutation behind an emission-owned executor, publishes compiler mod-data only after output and technology postconditions, flushes diagnostics on fatal assertion paths, replaces recursive researchability traversal, and uses output indexes rather than repeated recipe-by-pack scans. Bounded compiler telemetry records recipes, technologies, effects, graph structure, index scans, copies, accepted and rejected operations, diagnostics, and phase timing.

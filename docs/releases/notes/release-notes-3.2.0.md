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

The 3.2.0 candidate also fixes a Space Exploration plus Krastorio 2 startup crash caused by Space Exploration removing `kr-copper-cable-from-copper-ore` after MIR had emitted a copper-cable productivity effect for it. Space Exploration is now a hidden optional ordering dependency, MIR prunes any missing recipe-productivity targets still visible at its final safety pass, and a synthetic lifecycle fixture asserts that every final effect points to an existing recipe. This is a bounded startup-integrity fix, not a broad Space Exploration compatibility claim.

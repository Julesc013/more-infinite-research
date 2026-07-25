---
title: "MIR 3.2.0 Release Notes"
status: current
applies_to: "3.2.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-25
supersedes: []
superseded_by: []
---

# MIR 3.2.0 Release Notes

## Release artifact

MIR 3.2.0 uses exact C18 package-source commit `55a57548316729d89482c96dcecd7c65f26c6103`. The release archive is `dist/more-infinite-research_3.2.0.zip`: 1,026,915 bytes, 290 entries, and SHA-256 `C3F51041733A79AAE24D3882FC9FF63227A1455C6D63376B2DDE9858DC30520E`. Its normalized package-content and package-source SHA-256 is `1CDCBE41F644DB187153165617835FB8008DD69767A9BD6C78B396E8160065F5`. Publish this recorded ZIP without rebuilding it, then verify every downloaded public copy against the archive hash.

The maintainer selected C18 for `main` staging after deterministic builds, static validation, a targeted exact Space Age runtime, and hosted Branch Policy and MIR validation passed. Full exact-C18 no-reuse, approved-delta, upgrade, ecosystem/performance, schema-2 manual, protected qualification, and seal work was not completed; those omissions are recorded as explicit assurance exceptions rather than passes.

MIR 3.2.0 is a release-engineering overhaul built from the MIR 3.1.9 line plus the portable target-capability guard accumulated on `dev`. It introduces persistent content-addressed test evidence so unchanged scenarios can reuse exact prior proof while changed package, gameplay, settings, migration, fixture, harness, binary, and dependency inputs rerun the lanes they affect.

The release keeps the public setting IDs, generated technology IDs, migrations, and runtime-state namespaces from MIR 3.1.9. The explicit capability guard leaves Factorio 2.1 mod-data emission enabled but changes packaged data-stage source, so the 3.2.0 candidate requires fresh gameplay qualification rather than borrowing the 3.1.9 matrix. Version-only and package-only changes in later candidates still receive fresh deterministic-build, exact-ZIP load, and upgrade proof; gameplay scenarios are reused only when their declared effective domains are byte-identical.

No additional automatic recipe-family generation is enabled by default in 3.2.0. The release retains every established generated technology, adds one explicitly reviewed steel plate productivity stream, and moves candidate design, lifecycle, target integrity, and final emission behind common compiler contracts. Base games receive `recipe-prod-research_steel-1`; Space Age keeps vanilla `steel-plate-productivity` as the single owner for steel smelting and casting. These foundations improve safety and explainability without turning on a broader procedural technology set.

The Space Age stream set also adds default-on Nutrients productivity and Capture bot rocket productivity at `+10%` per level. Nutrients productivity targets only the exact yumako mash, bioflux, and biter egg forward-production recipes; spoilage recovery, fish, ATAN Ash sinks, and broad third-party nutrient matches remain excluded. Breeding productivity now has an exact regression proving pentapod egg coverage while retaining Space Age's productivity-exempt seed egg. Landfill productivity keeps landfill at `+10%` and foundation at `+5%`, and adds exact ice-platform and space-platform-foundation effects at `+2%` and `+1%`. Because those two platform recipes and capture robot rockets are not productivity-enabled upstream, MIR grants permission only to those exact recipes, only while Space Age is active, before immutable recipe facts are captured.

The final compiler path eliminates a discarded transient technology-catalog construction, uses copy-on-write branches for compiler-owned diagnostic designs, resolves final qualification from gate-only snapshots, and performs one complete validation on the authoritative post-selection catalog. These are construction-cost optimizations, not a relaxation of catalog validation. Packaged stream-default documentation is source-generated from `prototypes/mir/settings/defaults.lua`. All established technology toggles now default on, including spoilage preservation and the inserter capacity continuation. Those two remain explicitly `factory-disruptive`, sort in the first settings attention bucket, and receive automatic localized warnings in both their enable-setting and technology tooltips; default enablement does not weaken their classification.

The final candidate requires Factorio 2.1.11 or newer. MIR did not retain the earlier 2.1.8 dependency floor without exact final-candidate base and Space Age qualification. The shipped stable stream manifest also records native-owner binding for low-density structures, plastic, processing units, and rocket fuel, matching the compiler policy and repository stream authority.

Release qualification now produces one reviewable verification plan, stable per-scenario fingerprints, trusted evidence capsules, and one aggregate gate. Factorio 2.0 backports calculate independent target-specific fingerprints and cannot borrow Factorio 2.1 evidence.

The 3.2.0 candidate also fixes a Space Exploration plus Krastorio 2 startup crash caused by Space Exploration removing `kr-copper-cable-from-copper-ore` after MIR had emitted a copper-cable productivity effect for it. Space Exploration is a hidden optional ordering dependency, and MIR now uses one target-aware effect-contract authority to remove impossible known recipe, item, quality, space-location, ammunition-category, and entity references from both generated and external technology effects before final assertions. Space-location resolution recognizes concrete planet prototypes, so valid planet discovery effects are retained. The regressions retain valid effects and distinguish item grants at different qualities. This is startup-integrity evidence, not a broad Space Exploration, Krastorio, or Pyanodon compatibility claim.

Compiler safety now validates the combined existing-plus-planned technology graph with an iterative strongly connected component pass before emission, replaces whole-prototype base continuation cloning with an allowlisted builder, moves stream mutation behind an emission-owned executor, publishes compiler mod-data only after output and technology postconditions, flushes diagnostics on fatal assertion paths, replaces recursive researchability traversal, and uses output indexes rather than repeated recipe-by-pack scans. Bounded compiler telemetry records recipes, technologies, effects, graph structure, index scans, copies, accepted and rejected operations, diagnostics, and phase timing.

---
title: "ADR 0005: MIR 4 Local Beta Candidate Boundary"
status: current
applies_to: "MIR4-R0 through MIR4-4.0.0"
audience: release-manager
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-08-16
supersedes: []
superseded_by: []
---

# ADR 0005: MIR 4 Local Beta Candidate Boundary

## Context

The final programme design selects direct distribution codes, independently materialized target packages, and an offline emergency lane, while the live entry gate still forbids public 4.x before MIR 3 EOL.

The supplied programme documents also contain two implementation ambiguities: the proposed offline seal depends on a restoration receipt that is produced after sealing, and package-side proof material is both permitted and forbidden by different passages.

Exact Factorio 2.1.13, 2.0.77, 1.1.110, and 1.0.0 executables are not present in the local qualification environment, so deterministic construction cannot truthfully be promoted to runtime qualification.

## Decision

R0 may construct `4.0.21000` beneath `build/mir4/emergency-lane` as an unpublished local beta candidate; the four-target plan reserves `4.0.20000`, `4.0.11000`, and `4.0.10000`, but the executable materializer rejects them until a later EOL-bound admission authority exists.

The f210 candidate is admitted by the emergency lane; f200, f110, and f100 are non-authoritative shadows until the EOL and target-admission authorities advance.

`LegacyCompilerHostAdapterV1` captures each sealed terminal target source, changes only the projected distribution version, and emits through the existing package allowlist.

It cannot perform a semantic rewrite, a manual backport, publication, public identity allocation, or prototype mutation outside the existing emission boundary.

Each candidate undergoes at least three independently recaptured source-capsule and repeated deterministic package-construction runs, and must match its exact predecessor at every package-visible path except the generated package root and `info.json#/version`. These runs establish bounded same-tool repeatability, not checkout-independent C reconstruction; a toolchain-closed capsule remains open.

The candidate semantic root reuses the terminal semantic root, the candidate authority root additionally binds the plan, its exact imported authority closure, capsule, target, version, and candidate bytes, and the pre-qualification root binds that authority to the exact required engine without claiming an observation.

No evidence, signature, seal, receipt, schema, tool, fixture, or documentation file ships inside a mod package.

`MIR4BootstrapCanonicalJsonV1` is a narrow bootstrap record ABI for tool-created ordered objects, integer numbers, authority-ordered arrays, compact JSON, and UTF-8 without BOM; it does not settle the permanent post-4.0 canonicalization profile.

An offline seal binds the exact admitted f210 candidate manifest, current bootstrap plan, completed qualification, and passed human review. Verification requires an explicit trusted public-key path; the seal never treats its embedded public key as a trust anchor.

Two independently written, canonically and byte-identical publication dry-run bundles follow sealing and bind the verified seal. Restoration follows that paired idempotence proof, and the final emergency-lane completion record binds the independently verified seal, both post-seal dry runs, and the restoration receipt, removing the dependency cycle.

The pre-EOL emergency-lane completion record may close only after its exact-engine qualification, human review, proof-only signing, restoration, and dry-run gates pass. It is not a production release seal. No production release seal is issued while production signing custody, MIR 3 EOL, public allocation, or production release acceptance remains open.

Any candidate bytes distributed publicly become immutable and require an allocated distribution identity; a later release cannot overwrite the same version with different bytes.

## Consequences

The local ZIPs are useful deterministic beta artifacts, not releases and not evidence of Factorio runtime behavior.

The terminal `.9` archives, root package source, Git tags, public channels, and production keys remain unchanged.

The general repository move and compiler-authority replacement remain post-4.0 owner-by-owner work.

Release managers build the admitted candidate with `tools/mir.ps1 mir4 build-local-beta --target f210` and verify it with `tools/mir.ps1 mir4 check-local-beta --target f210`.

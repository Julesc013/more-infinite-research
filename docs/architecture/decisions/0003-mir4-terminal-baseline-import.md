---
title: "ADR 0003: MIR 4 Terminal Baseline Import"
status: current
applies_to: "MIR4-R0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-08-16
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-terminal-baseline-import
---

# ADR 0003: MIR 4 Terminal Baseline Import

## Context

MIR 4 must begin from sealed terminal products and their semantic evidence, not mutable branches or reconstructed development history. The `.5` bundles are immutable foundation baselines. The `.9` family has sealed packages, qualifications, reviews, tags, and GitHub publication receipts; Mod Portal custody remains incomplete.

## Decision

Terminal import is staged. `New-MIR3Dot9TerminalBaselines.ps1` creates nine deterministic logical bundle views. Each view contains 61 exact inputs: final manifests, candidate and freeze authority, fixed point, qualifications, review, seal, GitHub receipt, current Mod Portal custody observation, target profile, upgrade evidence, settings and compatibility records, complete package composition, normalized snapshot, and the full immutable `.5` foundation inventory.

The logical views are self-contained when constructed. Their source objects remain content-addressed in the repository to avoid nine copied writable truths. Each bundle is built twice with sorted paths and fixed ZIP timestamps; unequal bytes fail the capture.

The importer consumes only these bundle manifests and normalized snapshots. It preserves stable identities, settings, owners, aliases, tombstones, features and omissions, migration watermarks, claim maturity, locale coverage, engine qualification, and upgrade contracts. Unsupported or unobserved fields remain explicit omissions. Observed-only compatibility claims are never promoted.

Until Mod Portal custody and MIR 3 EOL are sealed, the result is a package-excluded shadow input with `semantic_authority = false`. It cannot generate or publish a package.

## Consequences

`tools/mir.ps1 mir4 check` proves that the capture, normalized import, entry gate, target registry, version projection, generated dashboard, and executable queue match all immutable inputs. It fails on archive, content, size, entry-count, source, tag, publication, manifest, qualification, seal, omission, registry, or self-hash drift.

Semantic authority remains MIR 3 until the EOL seal and exact equivalence gate authorize a one-way flip. Mutable branch history is never an import source.

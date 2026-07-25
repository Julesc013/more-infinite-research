---
title: "TechnologyApplicabilityEnvelope Schema"
status: current
applies_to: "3.2.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-18
supersedes: []
superseded_by: []
---

# TechnologyApplicabilityEnvelope Schema

A schema-1 `TechnologyApplicabilityEnvelope` makes an approval's reusable scope executable. It contains a stable `envelope_id`, supported Factorio lines, required features, an exact required-mod closure with optional versions, finite structural predicates, reviewed positive examples, reviewed negative examples, `maximum_new_matches`, and a content fingerprint.

The permitted predicates are `recipe.visible`, `recipe.productivity-eligible`, `output.deterministic-single-item`, `output.place-result-family`, `risk.none`, and `family.semantic-signature`. Predicates are identifiers from a finite authority, not executable expressions.

Lists and descriptor rows are normalized and sorted before fingerprinting. Both positive and negative examples and at least one required mod and structural predicate are mandatory. Evaluation fails closed on a target-line, feature, mod, mod-version, predicate, or newly matched-content mismatch.

Lua data-stage records use the MIR deterministic fingerprint implementation. Offline governance artifacts use canonical SHA-256 transport fingerprints. They are separate transports for the same reviewed material and must not be compared as if they were the same algorithm.

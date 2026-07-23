---
title: "ADR 0021: Hard Gate And Not-Applicable Proof"
status: current
applies_to: "3.2.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---

# ADR 0021: Hard Gate And Not-Applicable Proof

## Decision

`.mir/technology-hard-gates.json` is the single ordered hard-gate authority. Generated Lua is consumed by GenerationPlan, SafetyQualification, TechnologyCatalog, and the pure compiler.

A missing or unknown gate is a schema error. `not-applicable` is authoritative only when it binds an evaluator, named applicability predicate, exact input fingerprint, false predicate result, evidence, and their evidence fingerprint. It is never synthesized because an evaluator did not run.

Final selection admits only `qualified` alternatives. Proposals may be selected only in prequalification views.

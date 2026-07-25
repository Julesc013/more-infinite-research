---
title: "Offline Family Rule Synthesis"
status: current
applies_to: "3.2.0+"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-18
supersedes: []
superseded_by: []
---

# Offline Family Rule Synthesis

`scripts/Invoke-MIRRuleSynthesis.ps1` performs a bounded exhaustive search over the finite predicates in `.mir/rule-synthesis.json`. It consumes reviewed positive and negative examples plus stored ecosystem predicate snapshots. It does not run inside Factorio and cannot edit providers, family rules, compatibility policy, prototypes, or claims.

The objective is ordered: cover every reviewed positive, reject every reviewed negative, retain every mandatory hard predicate, minimize newly matched unreviewed snapshot content, minimize predicate count, and break ties lexicographically. The search refuses authorities with more than 20 predicates.

Example:

```powershell
.\scripts\Invoke-MIRRuleSynthesis.ps1 -Family mining-drill-manufacturing -OutputPath out\mining-drill-proposal.json
```

Every successful result has status `REVIEW_REQUIRED` and `production_mutation_authorized = false`. It includes exact corpus, snapshot, and authority SHA-256 hashes; selected predicates; the current-rule diff; newly matched content; and all five production-entry requirements. A proposal cannot enter production without a human-approved rule diff, positive fixtures, negative fixtures, a new-match report, and cross-ecosystem counterexample testing.

No opaque weights, runtime learning, executable expressions, or automatic promotion are permitted.

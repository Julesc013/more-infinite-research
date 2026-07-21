---
title: "Coverage Report"
status: current
applies_to: "3.1.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-20
supersedes: []
superseded_by: []
---

# Coverage Report

The internal schema-1 coverage report accounts for every final recipe exactly once. It is built after planned stream emission, adoption, and competing-owner transactions.

Normal Factorio loads publish `more-infinite-research-coverage-report` with data type `more-infinite-research.coverage-public`. This compact schema-1 projection contains summary counts, a coverage fingerprint, and a public fingerprint; it does not contain one row per recipe. Detailed diagnostics, automatic compiler preview/report mode, and validation fixtures additionally publish the complete row ledger as `more-infinite-research-coverage-report-internal` with data type `more-infinite-research.coverage-report-internal`, together with diagnostic audit rows.

Categories are `auto_attached`, `generated_family_covered`, `adopted_external`, `external_exact_owner`, `safe_skip`, `unsafe_skip`, `target_unsupported`, `ambiguous`, and `unclassified`. Ambiguous and unclassified rows are permitted only when they retain stable reasons; they are never permission to emit.

The summary records total, visible, productivity-eligible, and accounted recipe counts; dangling recipe-productivity effects; duplicate owners; candidate count; recipe and technology scan counts; technology count; technology-effect count; and graph-edge count. The internal artifact fingerprint covers the sorted rows and summary. The public coverage fingerprint covers the summary and internal schema identity, allowing ordinary loads to prove stable aggregate coverage without serializing the full ledger.

Release interpretation is stricter than load success. Accounted recipes must equal total recipes. Dangling effects and unintended duplicate owners must be zero. Every unresolved row must remain explicit and reviewable, and repeated identical inputs must produce the same fingerprint.

The report does not claim that every recipe should receive productivity. `safe_skip` and `unsafe_skip` are valid accounted outcomes when their reason is stable and safety remains fail-closed.

Recipes that return any input as an output are ineligible for automatic fixed-stream and family matching. Coverage records unowned rows as `unsafe_skip/shared_input_output_loop_risk`; a name, output match, or confidence score cannot override that veto. A canonical stream may opt in only for an exact reviewed process family, such as the declared coal-liquefaction oil-processing recipes and official bacteria-cultivation autocatalytic recipes.

RecipeFactV2 preserves all results but indexes productive outputs separately. A returned catalyst or container fully covered by `ignored_by_productivity` cannot make its recipe a candidate for that returned item or fluid. An otherwise unowned recipe with such a return remains `unsafe_skip/catalyst_or_nonproductive_return_requires_review` until a generic rule or pack proves its intended productive family.

---
title: "Coverage Report"
status: current
applies_to: "3.2.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# Coverage Report

The schema-1 coverage report accounts for every final recipe exactly once. It is built after planned stream emission, adoption, and competing-owner transactions, and is available in diagnostics or automatic-compiler `report` mode through the `more-infinite-research-coverage-report` `mod-data` prototype and audit rows.

Categories are `auto_attached`, `generated_family_covered`, `adopted_external`, `external_exact_owner`, `safe_skip`, `unsafe_skip`, `target_unsupported`, `ambiguous`, and `unclassified`. Ambiguous and unclassified rows are permitted only when they retain stable reasons; they are never permission to emit.

The summary records total, visible, productivity-eligible, and accounted recipe counts; dangling recipe-productivity effects; duplicate owners; candidate count; recipe and technology scan counts; technology count; technology-effect count; and graph-edge count. The artifact fingerprint covers the sorted rows and summary.

Release interpretation is stricter than load success. Accounted recipes must equal total recipes. Dangling effects and unintended duplicate owners must be zero. Every unresolved row must remain explicit and reviewable, and repeated identical inputs must produce the same fingerprint.

The report does not claim that every recipe should receive productivity. `safe_skip` and `unsafe_skip` are valid accounted outcomes when their reason is stable and safety remains fail-closed.

Recipes that return any input as an output are ineligible for automatic fixed-stream and family matching. Coverage records unowned rows as `unsafe_skip/shared_input_output_loop_risk`; a name, output match, or confidence score cannot override that veto. A canonical stream may opt in only for an exact reviewed process family, such as the declared coal-liquefaction oil-processing recipes.

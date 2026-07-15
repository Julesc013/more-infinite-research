---
title: "Adding A Family Rule"
status: current
applies_to: "3.1.0+"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# Adding A Family Rule

Start with a coverage report and prove that the candidate family is not already handled by a generic rule or exact external owner. Prefer structural evidence such as output item type, `place_result`, entity type, module tier, upgrade chain, and unlock graph. Do not introduce recipe-name classification for a family that can be identified structurally.

Add one schema-2 row to `prototypes/mir/families/rules.lua`. Declare all evidence, hard requirements, risk denials, grouping, tier, effect, ownership, science, prerequisite, target, action, and claim fields. A rule must fail closed when evidence is missing. Confidence may rank evidence but never override a hard safety gate.

Use an existing stream for attachment unless a stable generic-family identity was separately reviewed and added to the generated stream manifest and golden plan. Add arbitrary-name positive fixtures, structural decoys, external-owner cases, and negative loop or catalyst cases. Run the narrow fixture scenario, static validation, and the full Factorio matrix before raising a support claim.

Update `.mir/streams.yml`, `.mir/compatibility.yml`, `.mir/docs.yml`, and claim evidence when their governed surfaces change. Commit one rule and its focused tests independently from unrelated compatibility-pack work.

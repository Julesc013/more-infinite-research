---
title: "Scenario Manifest Schema"
status: current
applies_to: "3.1.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# Scenario Manifest Schema

`fixtures/compat-matrix/expected-scenarios.json` uses schema 2. Every target profile contains full declaration records rather than a list of names.

Required fields are `name`, `target_profile`, `kind`, `group`, and `surface`. `required_features` records the positive target capabilities needed by the scenario. The registry rejects bare names, duplicate names, target mismatches, unsupported kinds, and missing fields before validation starts.

Scenario kind, evidence group, and base/Space Age surface are declaration-owned. The runner no longer infers them from Factorio version tests or hard-coded scenario-name lists. Execution code may request a scenario, but it must resolve to exactly one compatible declaration first.

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

`fixtures/compat-matrix/expected-scenarios.json` uses schema 3. Every target profile contains full declaration records rather than a list of names.

Required fields are `name`, `target_profile`, `kind`, `group`, `surface`, `fixtures`, `settings`, `source_mode`, `timeout_seconds`, `tags`, `isolation`, and `assertions`. `required_features` records the positive target capabilities needed by the scenario. The registry rejects bare names, duplicate names, target mismatches, unsupported kinds, missing setup fields, nonpositive timeouts, and scenarios with zero declared assertions before validation starts.

Scenario kind, evidence group, base/Space Age surface, fixture set, settings, package source, timeout, selection tags, isolation policy, and assertion contract are declaration-owned. Runtime declarations use the one exact package built at the beginning of the run; a generated settings-only fixture changes startup defaults without modifying those package bytes. `-Scenario`, `-Group`, `-Tag`, `-Tier`, and `-List` resolve through this registry.

Every completed runtime or package result records the number of executed assertion contracts. Validation completeness fails when that number is zero. Logs remain diagnostic evidence rather than an implicit pass signal.

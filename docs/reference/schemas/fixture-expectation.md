---
title: "Fixture Expectation Schema"
status: draft
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Fixture Expectation Schema

Fixture expectations describe what a test fixture proves and which claim or
capability it protects.

Minimum fields:

| Field | Meaning |
| --- | --- |
| `fixture` | Fixture directory or scenario name. |
| `validates` | Behavior surface validated by the fixture. |
| `claim` | Optional compatibility claim ID. |
| `expected_streams` | Generated stream IDs expected to emit. |
| `expected_rejections` | Diagnostic-only or skipped behaviors expected. |

---
title: "Planner Report"
status: draft
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Planner Report

Planner reports summarize generated, skipped, rejected, and diagnostic-only decisions. Use them for report diffs before broadening a capability.

Current planner decision rows are exported through `prototypes/mir/report/decision_export.lua` before they reach `prototypes/mir/report/diagnostics_sink.lua`. The exporter is intentionally thin during the 3.0 transition: it preserves existing log and audit-row output while making `report/` the boundary for future JSON, fixture, and claim exports.

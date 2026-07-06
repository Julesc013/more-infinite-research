---
title: "StreamSpec Schema"
status: draft
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# StreamSpec Schema

A `StreamSpec` is the validated contract a planner hands to emission code before
MIR creates or mutates generated technology prototypes.

Required fields:

| Field | Meaning |
| --- | --- |
| `schema` | Schema version. |
| `manifest_id` | Stable generated stream manifest key. |
| `stream_key` | Internal stream key. |
| `technology_name` | Factorio prototype name to create or update. |
| `effects` | Validated technology effects. |
| `science` | Lab-compatible ingredient set. |
| `prerequisites` | Validated prerequisite list. |
| `migration_policy` | Stable, pending migration, or unreleased. |

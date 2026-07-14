---
title: "ADR 0007: Native Modifier Ownership Policy"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# ADR 0007: Native Modifier Ownership Policy

Status: Accepted for 3.0 planning

Date: 2026-07-07

## Decision

Recipe productivity and native modifiers are separate capability lanes. Native modifier owners are observed and preserved unless a narrow explicit policy says otherwise.

## Consequences

Mining-yield productivity, belt stack size, lab productivity, lab speed, and robot modifiers do not get folded into recipe-productivity generation.

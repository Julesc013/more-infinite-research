---
title: "ADR 0005: Generated ID And Migration Policy"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# ADR 0005: Generated ID And Migration Policy

Status: Accepted for 3.0 planning

Date: 2026-07-07

## Decision

Released generated technology IDs are save-compatibility surface area. Every generated stream must have a manifest row. Renames or removals require an explicit migration or documented unreleased status.

## Consequences

Generated stream IDs are append-only by default after release.

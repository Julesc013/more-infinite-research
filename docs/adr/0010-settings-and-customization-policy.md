---
title: "ADR 0010: Settings And Customization Policy"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# ADR 0010: Settings And Customization Policy

Status: Accepted for 3.0 planning

Date: 2026-07-07

## Decision

Settings should be feature-family or capability based. Avoid vague magic modes,
per-mod marketing labels, and settings for behavior that does not exist.

## Consequences

Advanced overrides may exist, but every override must be reported and remain
clearly separate from normal player settings.

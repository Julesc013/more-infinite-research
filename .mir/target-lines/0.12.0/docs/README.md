---
title: "More Infinite Research Documentation"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# More Infinite Research Documentation

MIR 3.x is a modular compatibility compiler for infinite research technologies.

## Start Here

- Players and modpack users: [User guide](user/README.md)
- Maintainers: [Maintainer guide](maintainer/README.md)
- Architecture: [Architecture overview](architecture/README.md)
- Capabilities: [Capability model](capabilities/README.md)
- Compatibility: [Compatibility model](compatibility/README.md)
- Exact schemas and references: [Reference](reference/README.md)
- Release planning: [Releases](releases/README.md)
- Architecture decisions: [ADR index](adr/README.md)
- Historical docs: [Archive](archive/README.md)

## Documentation Status

| Area | Status |
| --- | --- |
| User guide | Current for 3.x structure, not exhaustive |
| Architecture | Current for 3.x direction |
| Compatibility matrix | Evidence-bound, fixture-backed where claimed |
| Reference | Current for registered contracts |
| Archive | Historical, not authoritative |

## Documentation Rules

- One canonical page per topic.
- Every active Markdown file starts with metadata.
- Every Markdown file under `docs/` is registered in `.mir/docs.yml`.
- Archived pages are retained for historical context only.
- Compatibility claims require fixture or named load-check evidence.
- Generated stream names and schemas live in reference docs.

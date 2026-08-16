---
title: "More Infinite Research Documentation"
status: current
applies_to: "3.2.5 and the MIR 3 terminal programme"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-08
supersedes: []
superseded_by: []
---

# More Infinite Research Documentation

MIR 3 is a modular compatibility compiler for infinite research technologies. The `.5` target wave is published and immutable; all later MIR 3 corrections are synthesized in the [terminal `.9` programme](releases/mir-3-terminal-dot-9-programme.md). MIR 4 begins only after that programme is qualified, published, archived, and handed off.

## Start here

- Players and modpack users: [User guide](user/README.md)
- Current public description: [Mod Portal page](releases/mod-portal-page.md)
- Published and planned releases: [Release index](releases/README.md)
- Maintainers: [Maintainer guide](maintainer/README.md)
- Architecture: [Architecture overview](architecture/README.md)
- Capabilities: [Capability model](capabilities/README.md)
- Compatibility: [Compatibility model](compatibility/README.md)
- Exact schemas and references: [Reference](reference/README.md)
- Architecture decisions: [ADR index](adr/README.md)
- Historical docs: [Archive](archive/README.md)

## Documentation status

| Area | Status |
| --- | --- |
| Player guidance and Mod Portal copy | Current for the published `.5` wave |
| Release planning | One active terminal `.9` programme; no `.9` implementation yet |
| Architecture | Current for MIR 3; superseded 3.3/2.6 concepts route to MIR 4 |
| Compatibility matrix | Evidence-bound and fixture-backed where claimed |
| Reference | Current for registered contracts |
| Archive | Historical; never independent current authority |

## Documentation rules

- Keep one canonical active page per topic.
- Start every Markdown file under `docs/` with metadata and register it in `.mir/docs.yml`.
- Name the current replacement in every archived page.
- Bind compatibility claims to a fixture or named load-check.
- Treat generated views, including `todo.md`, as projections of machine-readable authority.
- Do not place docs in release ZIPs.

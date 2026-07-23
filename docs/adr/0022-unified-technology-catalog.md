---
title: "ADR 0022: Unified Technology Catalog"
status: current
applies_to: "3.2.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---

# ADR 0022: Unified Technology Catalog

## Decision

Fixed streams, generated families, native-owner patches, and base continuations share one catalog authority. Base continuation planning lives in `planner/base_continuations.lua`; its executor lives in `emit/base_continuation_executor.lua`.

The catalog preserves accepted, policy-rejected, sanitation-rejected, and graph-rejected base alternatives with the same total hard-gate vectors used for streams. Base candidates do not bypass selection, quality, promotion, migration, or result accounting.

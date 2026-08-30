---
title: "MIR 4 Maintainer Authority Map"
status: current
applies_to: "MIR 4.0.0+"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-maintainer-authority-map
---

# MIR 4 maintainer authority map

| Concern | Editable authority | Projection or evidence |
| --- | --- | --- |
| product and target identity | `.mir/releases/waves/mir4-r0/`, `.mir/targets.json` | target matrices and candidate manifests |
| player semantics | `.mir/streams.yml`, settings and compatibility authorities | terminal compiler artifacts |
| implementation ownership | `.mir/modules.yml`, active source roots | generated module and repository maps |
| documentation metadata | Markdown front matter | `.mir/docs.yml` and generated docs pages |
| verification selection | assurance and validation manifests | materialized verification plan and aggregate gate |
| release state | pre-freeze execution programme and event ledger | queue, dashboard, phase receipts |
| mutable operations | external `MIR_STATE_HOME` | journal and resume state |
| immutable preservation | external `MIR_ARCHIVE_HOME` | manifests, seals, signatures, restore receipts |

Generated projections are checked fixed points, never competing editable authorities. Historical terminal records remain immutable even when their location is not the final MIR4 layout.

The package root is a target materialization boundary. Preview and shadow sources are excluded from the player ZIP. Only the admitted emitter owns player technology mutation.

---
title: "MIR 4 Repository Fixed Point"
status: current
applies_to: "M4C02-09-24H private programme"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-08-23
supersedes: []
superseded_by: []
---
# MIR 4 repository fixed point

MIR 4 uses a shadow repository fixed point before any physical source move. The sole machine-readable authority is `.mir/control/repository-fixed-point.json`; `.mir/control/paths.yml` continues to own logical path resolution and `.mir/control-plane/ownership.json` continues to own writer selection.

The visible roots `governance`, `contracts`, `spec`, `src`, `targets`, `modules`, `sdk`, `tools/mir`, `tests`, `assurance`, `changes`, `releases`, `docs`, and `examples` each contain a generated `.mir-root.json`. A marker is a read-only projection. It neither becomes a second authority nor redirects a package writer.

Current package sources remain at their proven locations. A physical move is forbidden until old and new readers agree, old and new package trees agree, semantic and target roots agree, tests agree, rollback exists, and an independent audit accepts the exact transition.

Every repository path is classified as normative authority, generated projection, executable source, test fixture, reusable cache, durable evidence, process scratch, archive, obsolete, or unknown. An unknown path blocks deletion and cutover. The W01 tooling never grants deletion authority.

External local state is bound by environment name and exact path:

- `MIR_CACHE_HOME=C:\Projects\Factorio\cache\mir4`
- `MIR_STATE_HOME=C:\Projects\Factorio\state\mir4`
- `MIR_TEMP_HOME=C:\Projects\Factorio\tmp\mir4`
- `MIR_WORKTREE_HOME=C:\Projects\Factorio\more-infinite-research\.worktrees`
- `MIR_ARCHIVE_HOME=C:\Projects\Factorio\archive`
- `MIR_EVIDENCE_HOME=C:\Projects\Factorio\evidence\mir4`

Run `./tools/mir.ps1 mir4 repository check` for root parity and inventory, or `initialize` in the approved machine context to create and persist the external non-secret roots.

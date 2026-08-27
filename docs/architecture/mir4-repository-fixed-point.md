---
title: "MIR 4 Repository Fixed Point"
status: current
applies_to: "M4C02-09-24H private programme"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-08-27
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-visible-root-authority-migration
  - mir4-path-classification-and-external-roots
  - mir4-physical-move-gate
---
# MIR 4 repository fixed point

MIR 4 now migrates repository authorities one bounded family at a time while the proven player-package source remains fixed. `.mir/control/repository-fixed-point.json` owns the root state, `.mir/control/paths.yml` owns logical path resolution, and `.mir/control-plane/ownership.json` owns writer selection. `governance/repository/migrations/fixed-point-tooling-v1.json` is the separate authority for the first package-excluded tooling and test cutover; it does not replace any player authority.

The visible roots `governance`, `contracts`, `spec`, `src`, `targets`, `modules`, `sdk`, `tools/mir`, `tests`, `assurance`, `changes`, `releases`, `docs`, and `examples` each contain a generated `.mir-root.json`. A marker remains a read-only projection. The governance, contracts, assurance, tests, tools/mir, and releases roots additionally contain the real fixed-point migration authority, contracts, proof policy, canonical implementation/test, and deterministic receipt.

The canonical implementation is split by responsibility:

- domain rules: `tools/mir/domain/repository/RepositoryFixedPoint.ps1`;
- inventory port: `tools/mir/ports/repository/RepositoryInventory.ps1`;
- Git/filesystem adapter: `tools/mir/adapters/repository/GitRepositoryInventory.ps1`;
- projection writer: `tools/mir/application/repository/RepositoryFixedPoint.ps1`;
- command entrypoint: `tools/mir/cli/Invoke-MIR4RepositoryFixedPoint.ps1`;
- governed test: `tests/repository/Test-MIR4RepositoryFixedPoint.ps1`.

The former library, command, and W01 test paths are non-writable forwarders. They remain until every declared consumer uses the new paths, result parity and rollback have been rehearsed, and a separate sunset receipt is accepted. The deterministic current receipt is `releases/migrations/MIR4-Repository-Fixed-Point-Tooling-MigrationV1.json`.

Current package sources remain at their proven locations. This tooling/test cutover has no package-visible delta. A physical player-source move is forbidden until old and new readers agree, F210 and F200 package trees agree, semantic and target roots agree, direct upgrade and two-reload evidence agrees, rollback exists, and an independent audit accepts the exact transition.

Every repository path is classified as normative authority, generated projection, executable source, test fixture, reusable cache, durable evidence, process scratch, archive, obsolete, or unknown. An unknown path blocks deletion and cutover. The W01 tooling never grants deletion authority.

External local state is bound by environment name and exact path:

- `MIR_CACHE_HOME=C:\Projects\Factorio\cache\mir4`
- `MIR_STATE_HOME=C:\Projects\Factorio\state\mir4`
- `MIR_TEMP_HOME=C:\Projects\Factorio\tmp\mir4`
- `MIR_WORKTREE_HOME=C:\Projects\Factorio\more-infinite-research\.worktrees`
- `MIR_ARCHIVE_HOME=C:\Projects\Factorio\archive`
- `MIR_EVIDENCE_HOME=C:\Projects\Factorio\evidence\mir4`

Run `./tools/mir.ps1 mir4 repository check` for authority, receipt, root, compatibility-forwarder, and inventory parity. Run `initialize` only in the approved machine context to create and persist the external non-secret roots. Neither command authorizes deletion, source freeze, signing, promotion, tagging, or publication.

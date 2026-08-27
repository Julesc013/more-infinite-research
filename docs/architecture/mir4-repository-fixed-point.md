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

MIR 4 now migrates repository authorities one bounded family at a time while the proven player-package source remains fixed. `.mir/control/repository-fixed-point.json` owns the root state, `.mir/control/paths.yml` owns logical path resolution, and `.mir/control-plane/ownership.json` owns writer selection. `governance/repository/migrations/fixed-point-tooling-v1.json` is the separate authority for the first package-excluded tooling and test cutover. `governance/repository/migrations/canonicalization-tooling-v1.json` is its append-only successor for the canonical JSON implementation and T07 test cutover. Neither replaces any player authority.

The visible roots `governance`, `contracts`, `spec`, `src`, `targets`, `modules`, `sdk`, `tools/mir`, `tests`, `assurance`, `changes`, `releases`, `docs`, and `examples` each contain a generated `.mir-root.json`. A marker remains a read-only projection. The governance, contracts, assurance, tests, tools/mir, and releases roots additionally contain the real fixed-point migration authority, contracts, proof policy, canonical implementation/test, and deterministic receipt.

The canonical implementation is split by responsibility:

- domain rules: `tools/mir/domain/repository/RepositoryFixedPoint.ps1`;
- inventory port: `tools/mir/ports/repository/RepositoryInventory.ps1`;
- Git/filesystem adapter: `tools/mir/adapters/repository/GitRepositoryInventory.ps1`;
- projection writer: `tools/mir/application/repository/RepositoryFixedPoint.ps1`;
- command entrypoint: `tools/mir/cli/Invoke-MIR4RepositoryFixedPoint.ps1`;
- governed test: `tests/repository/Test-MIR4RepositoryFixedPoint.ps1`.

The former repository library, command, and W01 test paths are non-writable forwarders. The first receipt, `releases/migrations/MIR4-Repository-Fixed-Point-Tooling-MigrationV1.json`, is now a byte-pinned immutable historical predecessor and cannot be regenerated from current files. Its append-only successor is `releases/migrations/MIR4-Canonicalization-Tooling-MigrationV1.json`.

Canonical JSON now has one implementation at `tools/mir/domain/canonicalization/CanonicalJsonV1.ps1`, one governed functional test at `tests/canonicalization/Test-MIR4CanonicalizationDiagnostics.ps1`, and one successor-receipt writer at `tools/mir/application/canonicalization/CanonicalizationMigration.ps1`. The former library and T07 test paths are read-only forwarders. All compatibility paths remain until every declared consumer uses the final paths, result parity and rollback have been rehearsed, and a separate sunset receipt is accepted.

Current package sources remain at their proven locations. This tooling/test cutover has no package-visible delta. A physical player-source move is forbidden until old and new readers agree, F210 and F200 package trees agree, semantic and target roots agree, direct upgrade and two-reload evidence agrees, rollback exists, and an independent audit accepts the exact transition.

Every repository path is classified as normative authority, generated projection, executable source, test fixture, reusable cache, durable evidence, process scratch, archive, obsolete, or unknown. An unknown path blocks deletion and cutover. The W01 tooling never grants deletion authority.

External local state is bound by environment name and exact path:

- `MIR_CACHE_HOME=C:\Projects\Factorio\cache\mir4`
- `MIR_STATE_HOME=C:\Projects\Factorio\state\mir4`
- `MIR_TEMP_HOME=C:\Projects\Factorio\tmp\mir4`
- `MIR_WORKTREE_HOME=C:\Projects\Factorio\more-infinite-research\.worktrees`
- `MIR_ARCHIVE_HOME=C:\Projects\Factorio\archive`
- `MIR_EVIDENCE_HOME=C:\Projects\Factorio\evidence\mir4`

Run `./tools/mir.ps1 mir4 repository check` for root, historical-receipt, compatibility-forwarder, and inventory parity. `repository generate` may refresh only root-marker projections; it verifies but never rewrites the immutable first receipt. Run `./tools/mir.ps1 mir4 canonicalization-migration check` for the current successor receipt and append-only chain. Run `initialize` only in the approved machine context to create and persist the external non-secret roots. None of these commands authorizes deletion, source freeze, signing, promotion, tagging, or publication.

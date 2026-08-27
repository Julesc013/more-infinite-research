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

MIR 4 now migrates repository authorities one bounded family at a time while the proven player-package source remains fixed. `.mir/control/repository-fixed-point.json` owns the root state, `.mir/control/paths.yml` owns logical path resolution, and `.mir/control-plane/ownership.json` owns writer selection. `governance/repository/migrations/fixed-point-tooling-v1.json` is the separate authority for the first package-excluded tooling and test cutover. Canonicalization, diagnostics, target-key identity, and whole-platform tooling are byte-pinned append-only predecessors. `governance/repository/migrations/technology-acceptance-tooling-v1.json` is the current successor for the package-excluded technology-acceptance application, focused test, and release-history successor proof. None replaces any player authority.

The visible roots `governance`, `contracts`, `spec`, `src`, `targets`, `modules`, `sdk`, `tools/mir`, `tests`, `assurance`, `changes`, `releases`, `docs`, and `examples` each contain a generated `.mir-root.json`. A marker remains a read-only projection. The governance, contracts, assurance, tests, tools/mir, and releases roots additionally contain the real fixed-point migration authority, contracts, proof policy, canonical implementation/test, and deterministic receipt.

The canonical implementation is split by responsibility:

- domain rules: `tools/mir/domain/repository/RepositoryFixedPoint.ps1`;
- inventory port: `tools/mir/ports/repository/RepositoryInventory.ps1`;
- Git/filesystem adapter: `tools/mir/adapters/repository/GitRepositoryInventory.ps1`;
- projection writer: `tools/mir/application/repository/RepositoryFixedPoint.ps1`;
- command entrypoint: `tools/mir/cli/Invoke-MIR4RepositoryFixedPoint.ps1`;
- governed test: `tests/repository/Test-MIR4RepositoryFixedPoint.ps1`.

The former repository library, command, and W01 test paths are non-writable forwarders. The first receipt, `releases/migrations/MIR4-Repository-Fixed-Point-Tooling-MigrationV1.json`, is a byte-pinned immutable historical predecessor and cannot be regenerated from current files. Its canonicalization, diagnostics, target-key, and whole-platform successors are also byte-pinned history. `tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1` centralizes immutable predecessor validation and deterministic successor construction; it cannot rewrite any accepted receipt.

Canonical JSON has one implementation at `tools/mir/domain/canonicalization/CanonicalJsonV1.ps1` and one governed functional test at `tests/canonicalization/Test-MIR4CanonicalizationDiagnostics.ps1`. Stable diagnostics has one implementation at `tools/mir/domain/diagnostics/DiagnosticsV1.ps1` and a focused parity test at `tests/diagnostics/Test-MIR4DiagnosticsV1.ps1`. Target-key identity has one implementation at `tools/mir/domain/targets/TargetKey.ps1` and a focused parity test at `tests/targets/Test-MIR4TargetKey.ps1`. Accepted migration commands perform only byte, schema, digest, chain, and firewall verification; `generate` fails closed. Whole-platform application and test paths are accepted immutable predecessors. The current successor moves technology acceptance to `tools/mir/application/technology/TechnologyAcceptance.ps1`, adds the focused test at `tests/technology/Test-MIR4TechnologyAcceptance.ps1`, and binds the T14-through-T17 blocked successor proof used by published snapshot integrity. The old technology-acceptance library remains a read-only forwarder. All compatibility paths remain until every declared consumer uses the final paths, result parity and rollback have been rehearsed, and a separate sunset receipt is accepted.

Current package sources remain at their proven locations. This tooling/test cutover has no package-visible delta. A physical player-source move is forbidden until old and new readers agree, F210 and F200 package trees agree, semantic and target roots agree, direct upgrade and two-reload evidence agrees, rollback exists, and an independent audit accepts the exact transition.

Every repository path is classified as normative authority, generated projection, executable source, test fixture, reusable cache, durable evidence, process scratch, archive, obsolete, or unknown. An unknown path blocks deletion and cutover. The W01 tooling never grants deletion authority.

External local state is bound by environment name and exact path:

- `MIR_CACHE_HOME=C:\Projects\Factorio\cache\mir4`
- `MIR_STATE_HOME=C:\Projects\Factorio\state\mir4`
- `MIR_TEMP_HOME=C:\Projects\Factorio\tmp\mir4`
- `MIR_WORKTREE_HOME=C:\Projects\Factorio\more-infinite-research\.worktrees`
- `MIR_ARCHIVE_HOME=C:\Projects\Factorio\archive`
- `MIR_EVIDENCE_HOME=C:\Projects\Factorio\evidence\mir4`

Run `./tools/mir.ps1 mir4 repository check` for root, historical-receipt, compatibility-forwarder, and inventory parity. `repository generate` may refresh only root-marker projections; it verifies but never rewrites an immutable receipt. Run the canonicalization, diagnostics, and target-key migration `check` commands for their byte-pinned historical receipts, and `./tools/mir.ps1 mir4 whole-platform-migration check` for the current successor and complete append-only chain. Run `initialize` only in the approved machine context to create and persist the external non-secret roots. None of these commands authorizes deletion, source freeze, signing, promotion, tagging, or publication.

---
title: "MIR 4 Repository Fixed Point"
status: current
applies_to: "MIR 4.1+"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-09-05
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-visible-root-authority-migration
  - mir4-path-classification-and-external-roots
  - mir4-physical-move-gate
---
# MIR 4 repository fixed point

MIR 4 has completed the physical repository and current-product bridge fixed point. `.mir/control/repository-fixed-point.json` owns the root state, `.mir/control/paths.yml` owns logical path resolution, and `.mir/control-plane/ownership.json` owns writer selection. The first seventeen bounded migrations remain byte-pinned append-only predecessors. `governance/repository/migrations/current-product-bridge-retirement-v1.json` is the eighteenth successor and the sole current authority for bridge disposition. It binds zero current-product authority bridges while retaining only explicit read-only, package-excluded, owned, tested, and expiry-bounded historical compatibility paths.

The visible roots `governance`, `contracts`, `spec`, `src`, `targets`, `modules`, `sdk`, `tools/mir`, `tests`, `assurance`, `changes`, `releases`, `docs`, and `examples` each contain a generated `.mir-root.json`. A marker remains a read-only projection. The governance, contracts, assurance, tests, tools/mir, and releases roots additionally contain the real fixed-point migration authority, contracts, proof policy, canonical implementation/test, and deterministic receipt.

The canonical implementation is split by responsibility:

- domain rules: `tools/mir/domain/repository/RepositoryFixedPoint.ps1`;
- inventory port: `tools/mir/ports/repository/RepositoryInventory.ps1`;
- Git/filesystem adapter: `tools/mir/adapters/repository/GitRepositoryInventory.ps1`;
- projection writer: `tools/mir/application/repository/RepositoryFixedPoint.ps1`;
- command entrypoint: `tools/mir/cli/Invoke-MIR4RepositoryFixedPoint.ps1`;
- governed test: `tests/repository/Test-MIR4RepositoryFixedPoint.ps1`.

The former repository library, command, and W01 test paths are non-writable historical forwarders. The first receipt, `releases/migrations/MIR4-Repository-Fixed-Point-Tooling-MigrationV1.json`, and its successors through M42-02 are immutable historical predecessors. `tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1` centralizes immutable predecessor validation and deterministic successor construction; it cannot rewrite an accepted receipt. The current bridge receipt proves the exact predecessor identities, every evolved binding, the current authority set, and an empty package-visible delta.

Canonical JSON, diagnostics, target keys, package construction, validation, release orchestration, and each decomposed implementation retain one current implementation. Historical entrypoints cannot become writable authorities by being present or callable. They may be removed only after their declared compatibility-sunset review proves consumer absence, parity, and rollback; until then the retirement authority keeps each one finite and visible.

`src/mod` is the sole editable player-source authority, `targets` owns target identity, policy, overlays, and target files, and `TargetMaterializer` is the sole current package writer. Generated packages live below `build/packages`; the repository root is not an editable Factorio package. Historical root-package bytes remain read-only comparison custody and cannot be selected implicitly by current package, release, assurance, or control readers.

Every repository path is classified as normative authority, generated projection, executable source, test fixture, reusable cache, durable evidence, process scratch, archive, obsolete, or unknown. Unknown bridge state blocks deletion and release. No classification grants permission to delete dirty worktrees, unique evidence, public packages, unverified custody, or unexplained files.

External local state is admitted by environment name and then bound to an exact controlled path for each run:

- `MIR_CACHE_HOME`
- `MIR_STATE_HOME`
- `MIR_TEMP_HOME`
- `MIR_WORKTREE_HOME`
- `MIR_ARCHIVE_HOME`
- `MIR_EVIDENCE_HOME`

Run `./tools/mir.ps1 mir4 repository check` for root, immutable history, current bridge disposition, and inventory parity. The bridge writers may reproduce only their governed current authority and receipt; earlier migration receipts remain immutable. Characterization must report zero current-product, dual-write, package-authority, release/current-state, runtime/state/migration, public-claim, unowned, and unbounded bridges. None of these commands authorizes deletion, source freeze, signing, promotion, tagging, or publication.

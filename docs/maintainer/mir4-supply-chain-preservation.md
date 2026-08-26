---
title: "MIR 4 Supply-Chain and Preservation"
status: current
applies_to: "M4C02-09-24H T15 pre-freeze preparation"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-component-inventory-projections
  - mir4-supply-chain-provenance
  - mir4-release-capsule-preservation
---

# MIR 4 supply-chain and preservation

The machine authority is .mir/releases/governance/mir4/supply-chain.json. It defines the nine canonical component identities, standards, deterministic-construction rules, rights classifications, public/private custody boundary, and the pre-freeze transition firewall. It does not authorize source freeze, candidate allocation, production key generation, production signing, sealing, promotion, tagging, or publication.

## Generate the pre-freeze projections

Run .\tools\commands\mir4\Invoke-MIR4SupplyChain.ps1 from the repository root.

The command streams file and ZIP-entry hashes, writes canonical UTF-8/LF JSON, and produces one canonical component inventory plus SPDX 3.0.1, SPDX 2.3, and SLSA provenance projections. Supply an artifact-map JSON only when exact archives exist; otherwise the inventory records the governed source closure and does not imply that a candidate was allocated.

Use -RequireClean for accepted construction evidence. A dirty pre-freeze development run is diagnostic only.

## SPDX validation

The primary serialization is SPDX 3.0.1 JSON-LD. The implementation binds the official 3.0.1 schema by its recorded SHA-256, validates a generator-complete representative graph against that exact schema, and validates every element in the whole project graph against the closed MIR profile.

Do not pass the multi-megabyte whole-project graph directly to PowerShell Test-Json with the official schema. Its repeated anyOf expansion can consume the host memory reserve. The bounded validation method covers every generated element while keeping one official-schema representative for every generator shape.

SPDX 2.3 is a compatibility projection from the same component inventory. It is not a second writable inventory.

## Provenance boundary

SLSA v1 provenance binds the source commit and tree, contract/platform/toolchain roots, SOURCE_DATE_EPOCH, network-disabled policy, builder identity, component subjects, and output digests. Gameplay proof remains separate. Source-closure subjects are explicitly pre-freeze and must not be presented as released archive bytes.

## Rights and custody

The repository declares MPL-2.0 through LICENSE; the authority conservatively records concluded license and copyright as NOASSERTION. It does not invent ownership or a separate redistribution grant for binary artwork. Private engines, third-party archives, unredacted evidence, acquisition data, recovery material, credentials, and private keys remain outside ordinary repository and public-capsule history.

## Resource interruption

If a validator approaches the memory reserve, stop scheduling work, terminate the isolated child process, hash all completed immutable outputs, and write a resource-interruption receipt. A resource-context failure is not a semantic acceptance or rejection.

---
title: "MIR 4 Supply-Chain and Preservation"
status: current
applies_to: "M4C02-09-24H T15 pre-freeze preparation"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-27
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

## Proof-only attestation

Use the supply-chain command with -Attest, an explicit OpenSSH ssh-keygen path, an explicit workflow ref, and proof-only key paths below ignored build/ or .mir/local/. The optional -CreateProofKey switch creates only a disposable local Ed25519 proof key. It is not production signing authority and the command refuses to expose private key bytes or paths in the attestation.

The verifier binds the signed payload to the source commit and tree, canonical inventory root, SLSA digest, all nine component subjects, the exact F210 and F200 subject rows, workflow ref, trusted public-key fingerprint, local OpenSSH executable, and revocation snapshot. Verification rejects a wrong source, tree, inventory, provenance, subject, target, workflow, trusted root, revoked key, self-hash, or signature.

Never use proof-only key creation for T16. Production key generation, passphrase custody, recovery approval, production signing, and publication remain explicit maintainer gates.

## Construct the portable release capsule

Run .\tools\commands\mir4\Invoke-MIR4ReleaseCapsule.ps1 -Mode Build only after the supply-chain projection and four V1 developer-preview archives exist for the same clean source commit and tree. Pass the proof-only public key explicitly when the default ignored build location is not used.

The command verifies the component inventory, both SBOM projections, SLSA provenance, proof-only signature, trusted public key, revocation snapshot, and preview manifests before constructing anything. Repository, package-source, identity-set, and verifier component rows are hashed from one canonical Git archive of the exact source commit rather than mutable checkout bytes. Git runs with core.autocrlf=false and core.eol=lf while committed eol attributes remain authoritative, so the inventory and restored archive agree on both ordinary text and deliberately CRLF-bound authorities. It then writes one ZIP rooted at mir4-release-capsule. Public objects live at objects/sha256/<first-two-uppercase-hex>/<uppercase-sha256>; the manifest records logical roles separately from content identity, so duplicate bytes cannot create ambiguous custody.

The non-production capsule carries:

- the exact source archive and its commit/tree envelope;
- the current pre-freeze source and target record set;
- the canonical inventory, SPDX 3.0.1 and 2.3 projections, SLSA provenance, verified attestation, and proof-only public key;
- all four developer-preview archives and their embedded manifests;
- a proof-closure summary, deterministic restore instructions, and the public-safe private-custody index.

The manifest deliberately contains only a tag plan for v4.0.0. It records allocation and authorization as false. Construction is append-only: an existing archive or receipt may be reused only when its bytes are identical; a conflicting rewrite fails closed. The construction receipt distinguishes the normalized 1980-01-01T00:00:00Z policy instant from ZIP's timezone-free 1980-01-01T00:00:00 DOS clock, so verification never converts the stored clock through the host timezone.

## Public-safe and private custody partitions

The private-custody inventory names the exact F210 and F200 engine locks and separately classifies third-party mod closures, unredacted evidence, manual raw evidence, saves, acquisition data, and protected signing material. It contains no payload, machine path, credential, passphrase, or private key.

An unavailable private object is not silently treated as restored. The restoration receipt retains its stable object identity, availability state, and exact acquisition requirement. Engine reacquisition must follow the local engine authority: the current 2.1 Steam installation may be used as installed, while 2.0 and older engines remain under D:\Programs\Factorio\<version>. Never download, replace, retarget, or mutate a historical Steam depot without maintainer authority.

## Offline restoration

Run the capsule command with -Mode Restore, the exact capsule path, an empty restore root, and the exact OpenSSH ssh-keygen executable. The implementation has no network-capable construction or restoration path and records zero network calls; it never reads mutable GitHub state.

Restoration streams and rehashes every content-addressed object, safely expands the exact Git source, verifies contract, platform, and toolchain identity sets, verifies the F210/F200 package-source rows, checks all preview payload and embedded-metadata hashes, validates the inventory and SLSA binding, independently verifies the attestation and revocation inputs, validates the proof index, and exercises the publisher admission contract in dummy-none credential mode. The restored publisher receives no source checkout, package builder, signing key, credential, mutation, or production-publication authority.

The receipt is independent of its absolute restore path, so two clean roots produce the same record hash. The gate rejects a missing object, wrong digest, wrong target, wrong source or tree, revoked proof root, corrupt inventory, non-empty restore destination, or unavailable private payload presented as restored.

## Rights and custody

The repository declares MPL-2.0 through LICENSE; the authority conservatively records concluded license and copyright as NOASSERTION. It does not invent ownership or a separate redistribution grant for binary artwork. Private engines, third-party archives, unredacted evidence, acquisition data, recovery material, credentials, and private keys remain outside ordinary repository and public-capsule history.

## Runner and publisher confinement

Run `./tools/commands/mir4/Invoke-MIR4RunnerPublisherConfinement.ps1 -RequireClean` to write the commit-bound T15 confinement receipt. The verifier closes over every tracked and generated workflow source, requires every third-party action to match the full-SHA action lock, checks least-privilege permissions, and rejects direct workflow-dispatch input interpolation inside shell commands. Because the receipt raw-hashes workflow bytes, `.gitattributes` pins every workflow to LF and the verifier fails closed if either that Git attribute contract or the checked-out LF bytes are absent. This makes the workflow closure root invariant across clean worktrees and `core.autocrlf` settings.

Public pull requests run on secret-free hosted workers. Factorio-capable protected jobs use the `release-candidate` environment and are serialized to one heavy worker; public static work is capped at two lanes. Builders receive neither signing nor upload credentials, qualifiers cannot modify packages, and external mod closures receive acquisition-only Factorio credentials rather than release credentials. The publisher workflow has no action, checkout, source tree, builder, or private-key capability and must obtain an exact admission decision from its external seal verifier before its external client can run.

The confinement receipt is evidence, not publication authority. Its transition flags remain false even when every check passes.

## Resource interruption

If a validator approaches the memory reserve, stop scheduling work, terminate the isolated child process, hash all completed immutable outputs, and write a resource-interruption receipt. A resource-context failure is not a semantic acceptance or rejection.

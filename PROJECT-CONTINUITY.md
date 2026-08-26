# Project continuity

MIR is designed to remain auditable and releasable without one workstation, one hosting provider, or one maintainer's memory.

The continuity set consists of:

- source commit and tree identity;
- machine authorities, schemas, and generated fixed points;
- exact target and environment locks;
- deterministic player and preview archives;
- SBOM, provenance, signatures, seals, receipts, and public-byte readback;
- offline toolchain and restore evidence;
- explicit maintainer decisions and unresolved blockers.

Mutable state belongs under an external `MIR_STATE_HOME`; immutable preservation copies belong under an external `MIR_ARCHIVE_HOME`. Neither is a substitute for tracked manifests and public assets.

At handoff, the outgoing maintainer follows [Maintainer handoff](MAINTAINER-HANDOFF.md). A successor verifies the public key chain, restores the repository and archives offline, reruns the conformance profiles, and records a new custody event. No historical receipt is edited to name a new custodian.

See [Forking](FORKING.md) for an independent successor and [Governance](GOVERNANCE.md) for decision rights.

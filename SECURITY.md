# Security

Report suspected vulnerabilities privately to the repository maintainers through GitHub Security Advisories. Do not publish credentials, private keys, recovery shares, unpublished release locations, or exploitable archive examples in a public issue.

## Release security boundary

- Production signing keys and recovery inputs stay outside the repository.
- Public keys, verification policy, schemas, manifests, signatures, receipts, revocations, and readback evidence may be tracked or published.
- Release execution fails closed when the exact source, target, qualified environment, accepted assets or authorization is unavailable. The maintainer explicitly permits unsigned MIR5 GitHub releases when the enrolled key is unavailable; checksums are never presented as signatures.
- Published and frozen accepted assets are preserved by exact bytes. A correction creates a new reviewed candidate and inventory; historical MIR4 seals are never rewritten. MIR5 does not require a new technical-seal framework or a signature when the maintainer's unsigned-release authorization applies.
- Archives are rejected for absolute paths, traversal, links, duplicate normalized names, or files outside the allowlist.

Developer preview tooling has no signing, sealing, promotion, publication, prototype-mutation, runtime-state, or public-support authority.

For an incident, preserve the suspect bytes and logs, stop promotion, record the immutable event, rotate or revoke affected credentials outside the repository, and follow [the release runbook](docs/development.md#github-publication-after-acceptance).

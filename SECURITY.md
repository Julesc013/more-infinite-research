# Security

Report suspected vulnerabilities privately to the repository maintainers through GitHub Security Advisories. Do not publish credentials, private keys, recovery shares, unpublished release locations, or exploitable archive examples in a public issue.

## Release security boundary

- Production signing keys and recovery inputs stay outside the repository.
- Public keys, verification policy, schemas, manifests, signatures, receipts, revocations, and readback evidence may be tracked or published.
- Release execution fails closed when the exact source, target, environment, signer, ledger head, or authorization is unavailable.
- A sealed package is never rebuilt. A correction creates a new candidate and seal.
- Archives are rejected for absolute paths, traversal, links, duplicate normalized names, or files outside the allowlist.

Developer preview tooling has no signing, sealing, promotion, publication, prototype-mutation, runtime-state, or public-support authority.

For an incident, preserve the suspect bytes and logs, stop promotion, record the immutable event, rotate or revoke affected credentials outside the repository, and follow [the release runbook](RELEASE-RUNBOOK.md).

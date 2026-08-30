# Governance

MIR is governed by versioned machine authorities, independently reviewable evidence, and explicit human decisions. Repository prose explains those authorities but does not silently override them.

## Constitutional rules

- One fact has one writer.
- One change has one implementation.
- One target has one explicit disposition.
- One candidate has one complete certificate.
- One mutation is planned, journalled, verified, and compensable.
- One proposition plus exact input set has one proof identity.
- One published target is an independently qualified sealed package.

The stable player compiler and emitter remain authoritative until a named cutover proves parity, records rollback, and is admitted. Preview, shadow, experimental, and omitted components cannot self-promote.

## Decision rights

Automated executors may plan, dry-run, execute, resume, verify, compensate, and issue receipts only within their declared phase and inputs. They cannot invent maintainer playtest acceptance, production signing material, source-freeze authority, or external publication credentials.

Maintainers exclusively approve protected signing and recovery readiness, F210/F200 playtest receipts, source freeze, and the final promotion decision. No author approves their own release-critical evidence.

## Change custody

Normal work targets protected `dev` by pull request. The aggregate verification gate must pass before merge. `main` advances only through the governed promotion phase from the sealed candidate. Immutable release evidence is never rewritten; corrections are new events.

See [Contributing](CONTRIBUTING.md), [Release runbook](RELEASE-RUNBOOK.md), and [Project continuity](PROJECT-CONTINUITY.md).

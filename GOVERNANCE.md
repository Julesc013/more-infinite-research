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

Branch roles are defined in [the branch authority](.mir/branches.yml) and explained in [Contributing](CONTRIBUTING.md). Next-minor and next-major implementation, feature work, and refactors target protected `dev` by pull request. Protected `main` serves the latest stable MIR 4.x line, bounded stable corrections, repository-governance maintenance, and exact qualified development promotions. MIR 4.0.x corrections target protected `release/4.0` under its patch contract.

Routine implementation branches, public development pushes, pull requests, integration into `dev`, and primary-checkout synchronization are standing maintainer-authorized under [AGENTS.md](AGENTS.md). Required checks and enforced branch rules still apply; they are execution requirements, not a request for renewed routine permission. Source freeze, `main` promotion, signing and public release retain their separate acceptance and authorization requirements.

Read back the protected target after integration and complete required forward-port dispositions. `main` and `dev` may intentionally differ during next-release development; `dev` is not a read-only mirror. Preserve dirty or uniquely valuable local work. Immutable release evidence is never rewritten; corrections are new events.

See [Contributing](CONTRIBUTING.md), [Release runbook](RELEASE-RUNBOOK.md), and [Project continuity](PROJECT-CONTINUITY.md).

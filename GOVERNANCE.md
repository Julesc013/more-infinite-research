---
title: "MIR governance"
status: current
applies_to: "MIR development and publication"
audience: contributor
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-06
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-project-governance
---

# Governance

MIR uses the adopted specification, explicit maintainer decisions, shared source and independently reviewable evidence. The owning source, spec and target records define current facts; preserved MIR4 machine authorities remain historical inputs rather than an active parallel framework.

## Constitutional rules

- One fact has one writer.
- One change has one implementation.
- One target has one explicit disposition.
- One candidate has an exact source, asset inventory and explicit acceptance record.
- One mutation has an explicit owner, bounded preflight and independently checked resulting behavior.
- One proposition plus exact input set has one proof identity.
- Each retained stable edition requires its applicable independent qualification; additional best-effort historical artifacts carry their actual build status and missing native qualification explicitly.

The authored native-technology implementation and small Generator are the current player authority. The canonical source cutover is implemented; final current-package, consumer and native qualification remain release obligations. Preview, shadow, experimental and omitted components cannot self-promote. The [target contract](spec/targets.md) owns the distinction between retained edition acceptance and separately labelled best-effort artifacts.

## Decision rights

Contributors and automated tools work within the maintainer's authorized scope and selected inputs. They cannot invent player observations, signing material, publication credentials or additional authority.

Maintainers set acceptance and delegation. The active MIR5 authorization already covers implementation, qualification, source freeze, promotion and GitHub publication after acceptance; routine execution within it does not require repeated approval. Executors cannot invent human playtest observations, signing material or additional authorization. Release-critical evidence still needs independent review; an author cannot approve their own evidence.

## Change custody

Current branch and publication roles are defined in [AGENTS.md](AGENTS.md) and explained in [Contributing](CONTRIBUTING.md). MIR5 development and corrections target protected `dev` through pull requests; `main` contains the published product. Maintenance of an older published version starts from its exact tag on a separate task branch, as described in the [development-line policy](docs/development.md#development-line-and-maintenance-branches). Do not restore a parallel older implementation on `dev`.

Routine implementation branches, public development pushes, pull requests, integration into `dev` and primary-checkout synchronization are standing maintainer-authorized under [AGENTS.md](AGENTS.md). Required checks and enforced branch rules still apply; they are execution requirements. Source freeze, `main` promotion and public release use the accepted MIR5 authorization only after the applicable release gates pass. Signing, credentials and external-control changes retain their explicit authority boundaries.

Read back the protected target after integration and complete required forward-port dispositions. `main` and `dev` may intentionally differ during next-release development; `dev` is not a read-only mirror. Preserve dirty or uniquely valuable local work. Immutable release evidence is never rewritten; corrections are new events.

See [Contributing](CONTRIBUTING.md), [the release procedure](docs/development.md#github-publication-after-a-reviewed-verdict), and [current progress](docs/progress.md).

The maintainer authorizes MIR5 main promotion and GitHub publication after acceptance for the declared release maturity, with unsigned canonical tagging when the enrolled key is unavailable. A community prerelease may disclose the explicitly authorized unfinished Library and performance work; it still needs package integrity, exact provenance, upgrade safety, independent review and normal publication checks. Known package or upgrade-safety defects cannot be waived as beta polish. Stable requires all applicable verdicts. The [release procedure](docs/development.md#github-publication-after-a-reviewed-verdict) owns that route; original MIR4 seals and decisions remain historical evidence. Agent-managed publication is GitHub-only; the maintainer handles the Mod Portal. Credentials and repository controls retain their separate authorization boundaries.

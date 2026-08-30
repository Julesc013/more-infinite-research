---
title: "ADR 0030: Host-Neutral MIR Extension Protocol v1"
status: current
applies_to: "3.3.x, 2.6.x"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-08-04
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-extension-protocol-v1-decision
---

# ADR 0030: Host-Neutral MIR Extension Protocol v1

## Context

MIR's current compatibility packs are data-only, validated, deterministic, version-aware, evidence-bound, and unable to override hard safety. Their permanent public use is limited by a fixed shared `mod-data` prototype, a built-in-only provider registry, an oversized provider contract, one linear precedence model, and target-specific transport availability.

Ordinary players, mod authors, community maintainers, and compatible forks need a stable way to contribute compatibility without editing MIR or importing private compiler code. The design must work locally without a central service, must survive project abandonment or a successor host, and must not create a second mutation or claim authority.

## Decision

MIR 3.3.x and 2.6.x will implement MIR Extension Protocol v1 as a host-neutral, capability-negotiated, data-first semantic protocol independent of the MIR release version and of any single transport.

MEP-1 will provide:

- Unique automatic `mod-data` discovery on supported Factorio 2.1 targets.
- A versioned stage-local portable declaration bus for Factorio 2.0 and 2.1, subject to target conformance proof.
- A host-bound stable registration wrapper as a convenience only.
- A legacy adapter for the existing singleton compatibility-pack transport through at least the first complete 3.3/2.6 release pair.
- Independently versioned compatibility, profile, declarative-provider, presentation, proof, and bounded runtime fragments.
- Capability negotiation, namespaces, resource budgets, lifecycle freeze, semantic deduplication, and field-specific conflict resolution.
- A sealed hard-safety and prototype-mutation boundary.
- A separate experimental `TrustedAdapterV1` contract with immutable inputs, data-only outputs, declared semantic reads, and no mutation authority.
- A standalone SDK, offline builder, conformance suite, synthetic alternate host, and project-continuity bundle.

The existing compatibility policy authority remains the sole planning facade. Existing compiler records, plans, executors, journals, claim governance, and Control Plane evidence remain authoritative. MEP-1 contributes validated inputs and proof requirements; it does not create a parallel compiler or confer public support status.

## Consequences

- An ordinary compatibility contribution can ship outside the MIR repository and remain inert without a compatible host.
- The same semantic manifest can target MIR 3.3/Factorio 2.1 and MIR 2.6/Factorio 2.0 through different transports and explicit omissions.
- Registration order, repository ownership, official host name, and optional community catalogs are not policy authority.
- Unknown required capabilities and unknown safety-critical actions fail closed.
- Profiles and extensions may restrict behavior or choose among safe outcomes but cannot widen hard safety.
- A target mod that finalizes relevant prototypes after MIR requires a satisfiable load-order contract; extension discovery alone cannot solve it.
- A fork with a different internal mod name can preserve data-stage compatibility but needs an explicit bridge to inherit runtime state because Factorio persists storage per mod.
- Stable MEP-1 does not accept arbitrary Lua callbacks or direct prototype mutation.

## Alternatives rejected

### Keep the shared singleton prototype

Rejected because independent extensions would coordinate mutation of one transport object and remain coupled to one legacy discovery shape.

### Make `mod-data` the semantic API

Rejected because Factorio 2.0 target profiles lack that transport and because transport identity should not define protocol identity.

### Require official MIR as a dependency

Rejected because it prevents host-neutral packs, harmless host absence, and successor implementations.

### Expose compiler callbacks and executors

Rejected because arbitrary code would bypass bounded schemas, semantic impact, deterministic composition, and mutation ownership.

### Require a central extension registry

Rejected because startup must remain local, deterministic, offline-capable, and maintainable after the original service or project disappears.

## Reversal

Before the first stable MEP-1 release, individual fragment or transport designs may be removed through shadowed milestones. After MEP-1 is stable, a breaking change requires a new protocol major, a tested compatibility window, migration tooling where possible, and explicit deprecation or tombstone records.

The detailed protocol and delivery plan is [MIR Extension Protocol v1 Roadmap](../architecture/mir-extension-protocol-v1.md).

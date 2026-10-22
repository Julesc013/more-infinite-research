---
title: "MIR specification index"
status: proposed
applies_to: "MIR replacement development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-readme-specification
---

# MIR specification index

## Status and authority

This specification set is a proposed synthesis for the replacement implementation. On maintainer adoption, its normative requirements govern new product work. It does not declare that any implementation or native acceptance is complete.

Use this order to resolve conflicts: explicit current maintainer decisions and preserved player obligations; actual target-engine constraints; this specification; implementation and independent tests; explanatory documentation and agent task packets. Engine facts constrain feasibility, not product priority. When obligations conflict with an engine restriction, expose the conflict and obtain a documented decision. Never erase a user obligation by editing a test or an architectural slogan.

Historical source is evidence, not the current implementation design. Known historical bugs are not a parity requirement. Observed native behavior is evidence, not permission to invent a requirement. The request ledger retains its existing IDs and decisions; the seed continuity inventory below is not a second feature-request ledger.

## Task routing

| Task | Read |
|---|---|
| Replay, ordering, multiplayer or reproducible build | [Determinism](determinism.md), then the affected boundary |
| Any nontrivial implementation | [Architecture](architecture.md), then only its relevant row below |
| Research construction, ownership, progression | [Generator](generator.md) and [Settings](settings.md) |
| Overhaul/recipe/source binding | [Compatibility](compatibility.md) |
| Public data/runtime interface or SDK | [API](api.md), plus the appropriate lifecycle contract |
| Runtime, caps, Library, multiplayer | [Runtime](runtime.md) |
| Historical saves, carriers or state | [Migrations](migrations.md) |
| Engine adapter or package | [Targets and delivery](targets.md) |
| Speed, memory, scaling claim | [Performance](performance.md) |
| Test selection, acceptance or release | [Verification](verification.md) |
| Branches, documentation, source cleanup | [Repository](repository.md) |

[inventory/continuity.json](inventory/continuity.json) contains **unreconciled subjects**, not an exported technology catalogue or completed 83-request reconciliation. [inventory/sources.json](inventory/sources.json) distinguishes supplied proposals, live repository observations and external engine documentation. Do not load either file in Factorio.

## Terminology

- **Generator:** small prototype-stage construction helpers for explicitly authored research. Not a renamed discovery compiler, offline mandatory precompiler or generalized execution engine.
- **MIR API:** the single public integration name. Data and runtime are lifecycle surfaces, not separate brands.
- **MIR SDK:** optional developer examples, annotations and conformance utilities. It is not loaded by the player package.
- **Compatibility adapter:** a small explicit selection/binding module for known semantics.
- **Evidence:** an observed result tied to actual inputs. A plan, declaration, assertion count or candidate API example is not a native result.

Use stable requirement IDs such as `ARCH-01` and `API-01`; do not encode a product major into every requirement, file, function or module name. Keep API contract version, game target and product version separate.

## Readiness

A private slice may be incomplete, but stable replacement scope includes all delivered applicable research, settings, native continuations, overrides, runtime effects, Library behavior, useful bundled integrations and supported target subsets unless the maintainer explicitly approves a semantic change. No automatic deferral of existing features to a later minor release. Unimplemented requests and unconsumed previews retain their real status.

Root-path changes do not change these requirements. Relative links within this directory survive its mechanical relocation unchanged.

## Visual route and change record

Read the [architecture explainer](../../docs/mir5/architecture.md) for the lifecycle picture and the [visual atlas](../../docs/mir5/diagrams/index.html) for rendered diagrams. They explain these contracts; they do not override them. New product acceptance remains not run.

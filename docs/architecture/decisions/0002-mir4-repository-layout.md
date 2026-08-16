---
title: "ADR 0002: MIR 4 Repository Layout"
status: current
applies_to: "MIR4-R0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-08-16
supersedes: []
superseded_by: []
---

# ADR 0002: MIR 4 Repository Layout

## Context

MIR 3 ends with a mixed Factorio package root and package-excluded development plane. MIR 4 needs a durable separation between canonical semantics, lowering data, specifications, tooling, tests, documentation, and archived reconstruction authority without breaking the sealed terminal family.

## Decision

The post-EOL target layout separates canonical source, the Factorio platform adapter, and target projections:

```text
src/{semantic,compiler,policy,runtime,presentation,extensions}
platforms/factorio/{settings,prototype,runtime,package}
targets/<factorio-target>
spec
tools
validation
fixtures
docs
archive
.mir
build
dist
```

Existing Factorio root entrypoints, `prototypes/`, `locale/`, and `migrations/` remain canonical during R0. After equivalence is proven they become generated projections under `build/packages/<target>/<mod-name>_<distribution-version>/`.

No `src4/` or copied parallel product tree is permitted. Before MIR 3 EOL, the target layout is a shadow design only. After EOL, each migration slice declares its old and new owner, logical path ID, semantic reads and writes, generated mapping, parity proof, rollback, alias lifetime, and sunset condition. It then uses reviewed `git mv` operations and two clean reconstructions.

`main` remains the sealed 3.2.9 authority until the first stable MIR 4 promotion. `legacy` remains permanently frozen at 2.5.9. Lower MIR 3 targets remain tag-only.

## Consequences

The current `prototypes/`, Factorio entrypoints, `validation/`, and terminal reconstruction machinery are not moved or deleted by pre-R0 bootstrap. The first safe work is package-excluded authority, importer, equivalence, and restore tooling. Physical restructuring begins only after the EOL and cutover gates are true.

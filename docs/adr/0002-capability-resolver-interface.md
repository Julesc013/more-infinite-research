# ADR 0002: Capability Resolver Interface

Status: Accepted for 3.0 planning

Date: 2026-07-07

## Decision

Capability resolvers use the contract:

```text
discover -> classify -> propose -> validate -> emit -> diagnose
```

Each resolver has a stable ID and schema version.

## Consequences

Loaders, mining drills, ore processing, science packs, native modifiers, and
material families become capability lanes rather than per-mod generator code.


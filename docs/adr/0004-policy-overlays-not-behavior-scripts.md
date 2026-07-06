# ADR 0004: Policy Overlays, Not Behavior Scripts

Status: Accepted for 3.0 planning

Date: 2026-07-07

## Decision

Named compatibility files register declarative policy overlays. They do not
construct technologies directly.

## Consequences

Compat files can provide selectors, exact IDs, denylists, claims, and fixture
expectations while the compiler remains responsible for validation and emission.


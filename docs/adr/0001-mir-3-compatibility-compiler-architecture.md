# ADR 0001: MIR 3.0 Compatibility Compiler Architecture

Status: Accepted for 3.0 planning

Date: 2026-07-07

## Context

`2.2.0` proved a bounded procedural kernel with typed facts, capability
diagnostics, DecisionRecord-style rows, stream manifest metadata, compatibility
claims, negative fixtures, and report diff tooling. Future mod support will not
scale if every pack becomes a new generation branch.

## Decision

`3.0.0` is the compatibility compiler release. MIR will separate facts,
capabilities, classification, policy, planning, emission, reports, fixtures, and
migrations. Prototype mutation belongs only in the emission layer and only from
validated `StreamSpec` records.

## Consequences

- New mod support starts with policy and fixtures.
- New behavior classes start with capability resolvers.
- Unknowns and low-confidence candidates are reported before they emit.
- Public compatibility claims must be backed by claim manifests and fixtures.
- The release is architecture-led, not a broad feature bucket.


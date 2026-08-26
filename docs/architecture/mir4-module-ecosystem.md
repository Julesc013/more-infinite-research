---
title: "MIR 4 Module Ecosystem"
status: current
applies_to: "4.0.0 M4C02-09-24H"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
---

# MIR 4 Module Ecosystem

W05 completes the package-excluded developer-preview contract for extensions, public read APIs, bindings, and local extension tooling. It does not alter the Factorio player package or authorize a public ecosystem claim.

## Authority and flow

Target identity and transport facts come from W02. Compilation projections come from W03. Migration edge identity and continuity come from W04. W05 validates and resolves extension envelopes, then exposes copied, bounded projections through nine read APIs. W06 retains ProcessIR and external-effect semantics; W07 retains inspector, claims, and public compatibility presentation.

An extension contains 12 typed fragment kinds. It is canonical data, never a callback or executable. Recursive validation rejects callbacks, executors, prototype fields, raw mutable compiler context, and SafetyKernel overrides. Duplicate identities and namespaces, missing dependencies, dependency cycles, and declared conflicts fail closed. Capability gaps remain explicit review-required results.

## Target transports

f210 uses an extension-owned mod-data record shape. T11 implements the read-only side: exact data-type selection, bounded copied-envelope validation, deterministic dependency/conflict closure, inert host absence, and shadow-plan explanation. Admission remains blocked behind the existing terminal emitter. Neither W05 nor T11 writes `data.raw` or creates a prototype. f200 has a versioned namespaced stage-local bus confined to build/materializer scope. f110 through f015 use deterministic static manifests; f014 and f013 are opaque terminal-derived manifests. f012 through f006 are unavailable with evidence.

## API and SDK

Host Manifest, Query, Profile, Observation, Tooling, Target Provider ABI, Proof, Release, and Continuity Bundle responses are data-only, capability-labelled, deep-copied, paginated, and bounded to 128 items per page. An unavailable result carries status, reason, and evidence with a null total; it is not represented as zero.

Generated assets include JSON Schema, Lua builders, validators and the pure read-only mod-data collector, LuaLS annotations, TypeScript, Python, PowerShell, Markdown, canonical vectors, migration helpers, positive and negative fixtures, and the synthetic external reference extension. The local builder also provides `doctor`, `lock`, `diff`, `ci-init`, and `discover`; all writes are confined to `build/mir4`.

## Graduation boundary

No governed exact Industrial Revolution 4 repository/archive closure and accepted consumer scope is locally available. The synthetic external reference extension therefore proves preview conformance only. `BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER` remains open, `graduated` remains false, and no public support or publication authority is asserted.

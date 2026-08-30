---
title: "More Infinite Research 4.0.0 Candidate Release Notes"
status: current
applies_to: "MIR 4.0.0 candidate programme"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-24
supersedes: []
superseded_by: []
---

# More Infinite Research 4.0.0 Candidate Release Notes

MIR 4.0 preserves the proven MIR 3 player behavior while establishing a portable target-aware release system and a complete developer-preview platform.

## Players

- Target-specific packages prevent one Factorio line from silently inheriting another line's capabilities or omissions.
- Exact terminal predecessors preserve technology IDs, settings, research progress, runtime state, migrations and compatibility corrections.
- New inferred support remains diagnose-only: MIR handles a subject correctly, preserves it, requests an extension or review, omits it with evidence, or fails hard safety with a witness.
- Player packages contain only Factorio mod content. Developer tooling, schemas, fixtures and governance remain outside the ZIP.

## Modders and developers

- API/SDK V1 provides nine copied, bounded, capability-labelled contracts with JSON Schema, Lua/LuaLS, TypeScript, Python and PowerShell bindings.
- MEP V1 provides 12 typed data-only fragment kinds plus deterministic V0-to-V1 migration helpers.
- The synthetic reference extension and Inspector are first-party conformance consumers; independent production-consumer acceptance remains a component-graduation blocker, not a player-release blocker.
- Target-provider, normalized compiler, runtime/state, ProcessIR and opportunity catalogues run as deterministic non-authoritative previews or shadows.

## Candidate status

These notes describe the candidate programme, not a published release. F210 and F200 remain the mandatory public targets; F110 and F100 require independent admission; F018 through F013 are private experimental candidates. Production signatures, seals, tags, promotion and publication require a separate go/no-go.

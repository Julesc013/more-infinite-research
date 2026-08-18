---
title: "More Infinite Research 4.0.0 Candidate Release Notes"
status: current
applies_to: "MIR 4.0.0 candidate programme"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-18
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

- API/SDK V0 provides six read-only contracts, schemas, Lua and PowerShell bindings, fixtures, canonicalization vectors and stable diagnostics.
- MEP V0 provides a bounded data-only extension envelope.
- The reference extension and Inspector are independent first-party API consumers.
- Target-provider, normalized compiler, runtime/state, ProcessIR and opportunity catalogues run as deterministic non-authoritative previews or shadows.

## Candidate status

These notes describe the candidate programme, not a published release. f210 and f200 remain the mandatory public targets; f110 and f100 require independent admission; f018 through f013 are private experimental candidates. Production signatures, seals, tags, promotion and publication require a separate go/no-go.

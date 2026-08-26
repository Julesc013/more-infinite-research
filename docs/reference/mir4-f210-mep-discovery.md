---
title: "MIR 4 F210 Read-Only MEP Discovery"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-f210-extension-owned-mod-data-discovery
  - mir4-mep-host-absence-inertness
  - mir4-mep-read-only-shadow-planning
---

# MIR 4 F210 read-only MEP discovery

T11 implements discovery of extension-owned Factorio 2.1 `mod-data` records whose `data_type` is exactly `more-infinite-research.extension.v1`. The collector consumes an immutable snapshot, sorts records by prototype name, deep-copies each envelope, validates it through the same MEP V1 authority used by first-party tooling, resolves dependencies and conflicts, and emits shadow-plan explanations.

Run the reference snapshot through the repository or the extracted MEP preview archive:

    .\tools\mir.ps1 mir4 extension discover --discovery fixtures\mir4-mep-discovery-v1\positive\order-a.json --output build\mir4\mep-discovery

The output is `f210-mep-discovery.json`. `shadow-complete` means all matching envelopes validated and their dependency closure was deterministic. `quarantined` names stable diagnostics and authorizes no partial activation. Unrelated `mod-data` records are ignored by exact data type. The 32-extension and 64-snapshot-record bounds fail closed.

When `host.present` is false, the result is `host-absent-inert`: no envelope is validated or accepted, no dependency closure is constructed, and no shadow plan is produced. This models a standalone extension remaining harmless when no compatible host is installed.

Discovery is not admission. The F210 transport still reports `blocked-by-terminal-emitter`; the terminal emitter is unchanged, and no discovered fragment can reach `data.raw`, compiler context, runtime state, migrations, the SafetyKernel, signing, publication, or a public support claim. T11 is package-excluded developer-preview tooling and changes no player-package byte.

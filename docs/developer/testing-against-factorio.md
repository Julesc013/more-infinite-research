---
title: "Testing MIR Extensions Against Factorio"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-09-01
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-extension-factorio-testing-guide
---

# Testing MIR extensions against Factorio

Start with offline schema, closure, and shadow-plan conformance. Factorio execution is additional target evidence, not a substitute.

- F210 uses the latest official experimental Factorio 2.1 installation selected by Steam until the first official 2.1 stable transition. Do not substitute an older patch merely to reuse evidence.
- F200 uses the preserved `D:\Programs\Factorio\2.0\bin\x64\factorio.exe`.
- Record exact engine version, mod lock, settings, save or scenario identity, load result, reload result, and observed proposition.
- Run twice when determinism is claimed.

Before F210 work, run `./tools/mir.ps1 mir4 factorio-2.1-channel inspect --factorio <path> --output <path>`. A changed engine or API identity creates the required API, opportunity, compatibility, fixture, runtime, performance, and documentation review tasks. Tests use the newly selected patch immediately, but each produced proof remains exact-version and exact-binary bound.

MEP V1 does not install into the player package. F210 discovery tests captured extension-owned mod-data; it does not authorize MEP-driven emission.

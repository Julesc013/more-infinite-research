---
title: "Testing MIR Extensions Against Factorio"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-extension-factorio-testing-guide
---

# Testing MIR extensions against Factorio

Start with offline schema, closure, and shadow-plan conformance. Factorio execution is additional target evidence, not a substitute.

- F210 uses the current Steam Factorio 2.1 installation.
- F200 uses the preserved `D:\Programs\Factorio\2.0\bin\x64\factorio.exe`.
- Record exact engine version, mod lock, settings, save or scenario identity, load result, reload result, and observed proposition.
- Run twice when determinism is claimed.

MEP V1 does not install into the player package. F210 discovery tests captured extension-owned mod-data; it does not authorize MEP-driven emission.

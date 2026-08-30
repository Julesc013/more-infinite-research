---
title: "Your First MIR 4 Extension"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: tutorial
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-first-extension-tutorial
  - mir4-extension-developer-workflow
---

# Your first MIR 4 extension

This five-minute path creates and checks a data-only MIR Extension Protocol V1 envelope. It works in the repository and in the extracted mir4-mep-v1-preview.zip without a network connection.

    .\tools\commands\mir4\Invoke-MIR4Extension.ps1 -Command doctor
    .\tools\commands\mir4\Invoke-MIR4Extension.ps1 -Command init -ExtensionId org.example.first -Template minimal -OutputRoot build\first-extension
    .\tools\commands\mir4\Invoke-MIR4Extension.ps1 -Command validate -ExtensionPath build\first-extension\extension.json
    .\tools\commands\mir4\Invoke-MIR4Extension.ps1 -Command lock -ExtensionPath build\first-extension\extension.json -Target f210 -OutputRoot build\first-extension
    .\tools\commands\mir4\Invoke-MIR4Extension.ps1 -Command test -ExtensionPath build\first-extension\extension.json -Target f210
    .\tools\commands\mir4\Invoke-MIR4Extension.ps1 -Command package -ExtensionPath build\first-extension\extension.json -OutputRoot build\first-extension

Replace the placeholder subject_refs value with a stable subject identifier before treating the envelope as useful evidence. The F210 lock currently reports review-required: its extension-owned mod-data transport remains blocked by the terminal emitter. That is an explicit capability result, not a validation failure.

Use the all-fragments template to inspect every fragment kind or the unavailable template to exercise an explicit unavailable result. The archive also includes positive, reciprocal-conflict, unavailable, and V0-to-V1 migration examples under sdk/preview/mir4/mep-v1/examples.

To test F210 automatic discovery without changing a player package, use a captured mod-data snapshot:

    .\tools\mir.ps1 mir4 extension discover --discovery fixtures\mir4-mep-discovery-v1\positive\order-a.json --output build\first-extension\discovery

The read-only collector selects only `more-infinite-research.extension.v1`, validates the same envelopes used by `validate`, resolves dependencies and conflicts, and returns shadow plans. A snapshot with no host returns `host-absent-inert` with no accepted records or plans.

Compare two valid envelopes and create an offline CI scaffold:

    .\tools\commands\mir4\Invoke-MIR4Extension.ps1 -Command diff -BasePath old.json -CandidatePath new.json -OutputRoot build\first-extension
    .\tools\commands\mir4\Invoke-MIR4Extension.ps1 -Command ci-init -ExtensionPath extension.json -OutputRoot build\first-extension-ci

The scaffold expects the preview archive to be vendored at vendor/mir4-mep-v1-preview; validation itself performs no network access.

These commands never call extension callbacks because callbacks do not exist in MEP V1. They cannot mutate Factorio prototypes, compiler context, runtime state, migrations, the player package, the SafetyKernel, signatures, seals, publication state, or public support claims. Explain and test produce shadow plans only; package creates a developer archive containing extension.json and a non-authoritative manifest.

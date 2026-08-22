---
title: "MIR 4 Platform Component Matrix"
status: current
applies_to: "4.0.0 M4C01"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-18
supersedes: []
superseded_by: []
---
# MIR 4 Platform Component Matrix

Generated from `spec/platform/mir4-preview-v0/platform.json`.

| Component | Maturity | Mode |
| --- | --- | --- |
| `source-distribution-codec` | stable | authoritative |
| `target-identity-predecessor-contracts` | stable | authoritative |
| `legacy-compiler-host-adapter-v1` | stable | bootstrap |
| `target-materializer` | stable | authoritative-for-admitted-targets |
| `package-surface-lock` | stable | authoritative |
| `release-dag` | stable | authoritative |
| `api-sdk-v0` | preview | read-only-package-excluded |
| `mep-v0` | preview | data-only-package-excluded |
| `query-profile-observation-v0` | preview | read-only-package-excluded |
| `inspector-v0` | preview | query-consumer-package-excluded |
| `target-provider-abi-v0` | preview | build-time-package-excluded |
| `normalized-compiler-v0` | shadow | compare-only |
| `safety-kernel-policy-engine-boundary-v0` | shadow | dependency-audit |
| `runtime-state-model-v0` | shadow | inventory-only |
| `process-ir-v0` | shadow | parity-and-loop-diagnostics |
| `autonomous-synthesis-v0` | shadow | diagnose-only |
| `historical-target-providers-v0` | experimental | private-build-only |

The conformance gate enforces the eight non-interference rules and keeps every non-stable surface outside player packages.

---
title: "MIR 4 Platform Component Matrix"
status: current
applies_to: "4.0.0 M4C02-09-24H"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-23
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
| `target-provider-abi-v1` | preview | build-time-package-excluded |
| `normalized-compiler-v1` | shadow | reference-aggregate-compare-only |
| `feature-setting-aggregate-v1` | shadow | reference-only-package-excluded |
| `provider-micro-protocol-v1` | shadow | legacy-adapter-package-excluded |
| `merge-law-catalogue-v1` | shadow | twelve-adapted-complete-static |
| `safety-kernel-policy-engine-boundary-v0` | shadow | dependency-audit |
| `runtime-state-model-v1` | shadow | field-aware-contract-verifier |
| `runtime-registration-plan-v1` | shadow | existing-dispatcher-law-verifier |
| `migration-graph-v1` | shadow | explicit-private-transition-contract |
| `continuity-bundle-v1` | preview | private-redacted-package-excluded |
| `mep-v1` | preview | typed-data-only-package-excluded |
| `extension-closure-v1` | preview | deterministic-resolver-package-excluded |
| `api-sdk-v1` | preview | bounded-copied-data-only-package-excluded |
| `synthetic-reference-consumer-v1` | preview | blocked-independent-production-consumer |
| `process-ir-v0` | shadow | parity-and-loop-diagnostics |
| `autonomous-synthesis-v0` | shadow | diagnose-only |
| `historical-target-providers-v0` | experimental | private-build-only |

The conformance gate enforces the eight non-interference rules and keeps every non-stable surface outside player packages.

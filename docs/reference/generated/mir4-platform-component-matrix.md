---
title: "MIR 4 Platform Component Matrix"
status: current
applies_to: "4.0.0 M4C10-WHOLE-4X-IN-4.0"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-24
supersedes: []
superseded_by: []
---
# MIR 4 Platform Component Matrix

Generated from `spec/platform/mir4-preview-v0/platform.json`. V1 is the current release-facing developer preview; V0 remains a superseded compatibility input for migration testing only.

| Component | Maturity | Mode |
| --- | --- | --- |
| `source-distribution-codec` | stable | authoritative |
| `target-identity-predecessor-contracts` | stable | authoritative |
| `legacy-compiler-host-adapter-v1` | stable | bootstrap |
| `target-materializer` | stable | authoritative-for-admitted-targets |
| `package-surface-lock` | stable | authoritative |
| `release-dag` | stable | authoritative |
| `whole-platform-programme-v1` | stable | package-excluded-4.0-consolidation-authority |
| `uppercase-f-target-presentation-v1` | stable | canonical-display-with-legacy-input-normalization |
| `technology-acceptance-queue-v1` | preview | one-technology-at-a-time-non-mutating-review-queue |
| `api-sdk-v0` | preview | superseded-compatibility-input-package-excluded |
| `mep-v0` | preview | superseded-migration-input-package-excluded |
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
| `process-ir-v1` | preview | synthetic-parity-exact-target-snapshot-blocked |
| `effect-channel-registry-v1` | preview | owner-references-and-opaque-preservation |
| `autonomous-synthesis-v1` | preview | diagnose-conservative-experimental-no-player-mutation |
| `compatibility-subject-ledger-v1` | preview | multidimensional-private-evidence-nontransferable |
| `compatibility-factory-v1` | preview | data-only-allowlisted-zip-no-code-generation |
| `inspector-v1` | preview | offline-bounded-accessible-package-excluded |
| `historical-target-providers-v0` | experimental | private-build-only |

The conformance gate enforces the eight non-interference rules and keeps every non-stable surface outside player packages.

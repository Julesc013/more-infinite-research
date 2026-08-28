---
title: "MIR 4 Whole Platform Matrix"
status: current
applies_to: "4.0.0 M4C10"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-27
supersedes: []
superseded_by: []
source_of_truth_for:
  - generated-mir4-whole-platform-maturity
---
# MIR 4 whole platform matrix

Generated from `.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json`. Every former 4.0 through 4.17 area is assigned to source release 4.0.0; maturity and cutover remain explicit.

| Former slot | Platform area | 4.0 maturity | Completion | Blockers |
| --- | --- | --- | --- | --- |
| `4.0` | `release-identity-and-package-foundation` | stable | implemented-private | BLOCKED-HUMAN-SECRET-INPUT, MAINTAINER-MANUAL-PLAYTEST |
| `4.1` | `repository-and-authority-fixed-point` | mixed | append-only-repository-through-processir-exact-application-cli-and-test-writer-cutovers-with-compatibility-readers | remaining-repository-authority-families, package-visible-source-cutover-parity-and-independent-acceptance |
| `4.2` | `generalized-target-compiler` | preview | implemented-private-provider-abi | BLOCKED-F018-EXACT-ENGINE, BLOCKED-MUSEUM-CUSTODY |
| `4.3` | `semantic-contribution-compiler` | shadow | implemented-reference-aggregate | none |
| `4.4` | `feature-manifest-and-setting-spec` | shadow | implemented-reference-aggregate | none |
| `4.5` | `safety-kernel-policy-engine-and-merge-laws` | shadow | implemented-non-authoritative | none |
| `4.6` | `governed-lifecycle-plans-and-executors` | mixed | stable-terminal-authority-plus-shadow-aggregate | none |
| `4.7` | `runtime-feature-and-state-kernel` | mixed | stable-terminal-runtime-plus-shadow-contracts | MAINTAINER-MANUAL-PLAYTEST |
| `4.8` | `migration-graph-and-continuity` | preview | implemented-private-contracts | MAINTAINER-MANUAL-PLAYTEST |
| `4.9` | `mep-and-module-ecosystem` | preview | implemented-data-only-preview-canonical-application-cli-and-test-cutover | BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER |
| `4.10` | `api-sdk-and-tooling-bindings` | preview | implemented-generated-preview | BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER |
| `4.11` | `process-ir-and-effect-channels` | preview | implemented-synthetic-and-exact-target-parity-preview-canonical-application-cli-and-test-cutover | BLOCKED-EXACT-ARCHIVE-CUSTODY-F200-K2SO |
| `4.12` | `autonomous-synthesis-and-candidate-grammar` | preview | implemented-diagnose-conservative-experimental-canonical-application-cli-and-test-cutover | BLOCKED-EXACT-ARCHIVE-CUSTODY-F200-K2SO, MAINTAINER-TECHNOLOGY-ACCEPTANCE |
| `4.13` | `offline-inspector-workbench` | preview | implemented-offline-preview | BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER |
| `4.14` | `compatibility-factory-and-support-assessment` | preview | implemented-data-only-preview | none |
| `4.15` | `assurance-scale-proof-reuse-and-release-budgets` | shadow | implemented-proposal-and-offline-drill | BLOCKED-TRUSTED-TIMING-CAPACITY-EVIDENCE |
| `4.16` | `historical-museum-and-successor-host` | mixed | private-historical-plus-blocked-museum-plus-synthetic-host | BLOCKED-MUSEUM-CUSTODY, BLOCKED-FUTURE-INDEPENDENT-PRODUCTION-HOST |
| `4.17` | `ecosystem-technology-acceptance-and-tuning` | preview | implemented-queue-canonical-application-migrated-compatibility-reader-retained | MAINTAINER-TECHNOLOGY-ACCEPTANCE |

Canonical human-facing target keys use uppercase `F`, for example `F210` and `F200`. Existing lowercase target IDs remain accepted only as compatibility inputs and inside immutable historical evidence.

Source inclusion is not player-authority promotion. Preview, shadow, experimental, omitted, and blocked surfaces remain fail-closed until their named cutover gates pass.

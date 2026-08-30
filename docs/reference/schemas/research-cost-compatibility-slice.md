---
title: "Research-Cost Compatibility Slice Schema"
status: current
applies_to: "3.2.5+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-05
supersedes: []
superseded_by: []
source_of_truth_for:
  - research-cost-compatibility-slice-schema
  - research-cost-target-disposition-projection
---

# Research-Cost Compatibility Slice Schema

`ResearchCostCompatibilitySlice` schema 1 and ABI `mir-research-cost-compatibility-slice-v1` expose one bounded end-to-end proposition: `mir-research-cost-neutral-default-parity-v1`.

The compiler constructs the slice only after its immutable `CompilerInput` and final `APPLIED` `CompilerResult` have passed their trust boundaries. The artifact binds the accepted research-cost semantic set to the compilation and qualification fingerprints, planned and final result identities, mutation journal, realized output, and exact runtime-environment fingerprint. It does not rescan prototypes or acquire mutation authority.

## Terminal disposition

Exactly one terminal disposition is derived from the realized cost models:

| Status | Reason | Meaning |
| --- | --- | --- |
| `SUPPORTED` | `neutral-default-semantic-parity-proven` | At least one accepted model exists and every accepted model retains the neutral zero increment. |
| `NOT_APPLICABLE` | `neutral-default-not-active` | One or more accepted models use an explicit nonzero increment, so the default-parity proposition is not the active configuration. |
| `UNSUPPORTED` | `no-research-cost-models-realized` | No accepted model exists; the artifact fails closed without claiming parity. |

The typed `mir-research-cost-proof-assertion-v1` assertion uses the `SEMANTIC` dimension and mirrors the disposition as `PASSED`, `NOT_APPLICABLE`, or `FAILED`. Its fingerprint covers the proposition, exact environment, semantic-set fingerprint, and compiler evidence linkage. Any field or target-disposition change invalidates the assertion or support fingerprint.

## Bounded public support projection

The public artifact kind is `mir-research-cost-support-public`, with a hard 16 KiB canonical-byte limit. It publishes counts, the semantic-set fingerprint, one deterministic model sample, exact included/omitted counts, stable reason and remediation codes, and no paths or mod names. The support projection cannot change compilation output.

Factorio 2.1 publishes the artifact as `more-infinite-research-research-cost-compatibility` with data type `more-infinite-research.research-cost-compatibility-public`. Its terminal target classification is `target-native-equivalent` and its transport is `mod-data`.

Factorio 2.0 has the explicit `portable-with-adapter` disposition because the count-formula semantic contract projects but `mod-data` does not. Its selected transport is the bounded `validation-log` envelope. The row deliberately remains `requires-exact-target-proof`; it is a machine-readable implementation disposition, not 2.5.5 release or qualification authority.

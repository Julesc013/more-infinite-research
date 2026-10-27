---
title: "Implementation reading guide"
status: current
applies_to: "MIR development"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-27
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-implementation-reading-guide
---

# Implementation reading guide

Read the implementation and its governing contract together. The [specification index](../../spec/README.md) owns requirements, `source/` owns implementation, tests own independent expectations and [progress](../progress.md) owns exact qualification status.

| Responsibility | Implementation | Contract or check |
|---|---|---|
| Authored native research and local publication | [Generator](../../source/research/generator.lua), [settings](../../source/research/settings.lua), [data finalizer](../../source/data-final-fixes.lua) | [Generator](../../spec/generator.md), [settings](../../spec/settings.md), [compatibility](../../spec/compatibility.md) |
| Events, caps and saved state | [Bootstrap](../../source/runtime/bootstrap.lua), [lifecycle](../../source/runtime/lifecycle.lua) | [Runtime](../../spec/runtime.md), [migrations](../../spec/migrations.md) |
| Library and public integration | [Library](../../source/runtime/library.lua), [data API](../../source/api/v1/data.lua), [runtime API](../../source/api/v1/runtime.lua) | [API guide](../api.md), [SDK](../../sdk/README.md), [API contract](../../spec/api.md) |
| Engine selection and package composition | [Target adapter](../../source/platform/target.lua), [packager](../../tools/package.py), [release adapter](../../tools/release.py) | [Targets](../../spec/targets.md) |
| Independent verification and current commands | [Host driver](../../tests/Test-MIR5HostControls.ps1), [development guide](../development.md) | [Verification](../../spec/verification.md), [performance](../../spec/performance.md) |

Use the host driver's `-Plan` output before selecting checks and keep native, save, client and performance observations under their exact inputs. A current document, a host test or a built package does not close a missing native acceptance gate.

## Superseded implementation drafts

The former API `1.0.0-draft.2` pseudocode, draft review and proposed opposing-test catalogue were temporary explanatory material. Their normative requirements remain governed by the adopted specification; their original proposal text and IDs remain in the exact Git references below. Current source, SDK examples, executable controls and the progress record replace their active reading instructions. This retirement neither marks unimplemented proposals delivered nor changes an acceptance threshold.

- [blueprint.md](https://github.com/Julesc013/more-infinite-research/blob/902c4ff8187679ac80e637b169f9fd96a98ff90f/docs/implementation/blueprint.md) — original SHA-256 `F021F1DD82E9CF5B935B2CB74EC4602452B76D0E5F4568710B69B9FC3259D08A`.
- [review.md](https://github.com/Julesc013/more-infinite-research/blob/902c4ff8187679ac80e637b169f9fd96a98ff90f/docs/implementation/review.md) — original SHA-256 `199CE1AA70ED82ADC824F922B1EF994BB39F3AFA6D61DECF545C7F1688E656EB`.
- [opposing-tests.md](https://github.com/Julesc013/more-infinite-research/blob/902c4ff8187679ac80e637b169f9fd96a98ff90f/docs/implementation/opposing-tests.md) — original SHA-256 `045C7AE96ACCBE229B5E045CA8380FE056E278A932BABADC953857C75CEA173A`.

---
title: "MIR 4 Inspector and Compatibility Factory"
status: current
applies_to: "4.0.0 M4C02-09-24H"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-08-23
supersedes: []
superseded_by: []
---
# MIR 4 Inspector and Compatibility Factory

W07 is a package-excluded read model. It copies bounded DTOs from the target, semantic compiler, runtime/migration, module ecosystem, ProcessIR, terminal compatibility, terminal claim, and SOL07 evidence authorities. It does not own or reinterpret any of those authorities.

The one-way data flow is:

```text
terminal claims and compatibility policy + W02–W06 records + SOL07 receipt
  -> CompatibilityIndex copied DTOs
  -> multidimensional SupportAssessment ledger
  -> offline Inspector V1 and data-only Compatibility Factory bundle
```

`tools/lib/mir4/SupportAssessment.ps1` is the sole W07 subject-assessment owner. Every named ecosystem has separate availability, hard-safety, implementation, target-portability, migration, proof, claim, evidence, and revocation dimensions. There is no modpack-wide support Boolean. Evidence from SOL07 is labeled `historical-development-evidence-nontransferable`; it cannot qualify a different source, candidate, target, public claim, or release.

`tools/lib/mir4/CompatibilityFactory.ps1` implements the closed priority order from generic correction through preserve/review/omit and an experimental trusted adapter last. A selected lower option retains explicit reasons for rejecting every higher option. Its deterministic ZIP contains only JSON, schemas, provenance, plans, explanations, portability, and ledger data. Lua, PowerShell, callbacks, prototype paths, runtime code, migrations, and undeclared entries are rejected.

Inspector V0 remains unchanged under `sdk/preview/mir4/inspector`. Inspector V1 lives separately under `sdk/preview/mir4/inspector-v1`. V1 accepts only `MIR4InspectionBundleV1`, renders eleven fixed bounded sections, uses native keyboard controls and accessible tables/live regions, keeps strings in a localization catalogue, and has a network-denying content security policy. It performs no upload, remote fetch, runtime polling, or mutation.

The named ecosystem ledger preserves the current evidence boundary:

- Base/official, AAI, BZ, and Bob have narrow f210 load observations only.
- K2/K2SO has bounded f210 science-phase evidence and private f200 characterization; neither transfers to another target or a public claim.
- IR3, IR4, Angel, and Pyanodons remain `review-required/no-governed-exact-archive-closure`.
- Space Exploration remains `extension-required` with no complete current exact dependency closure.
- IR4 additionally retains `BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER`.

The exact W07 records are `MIR4_INSPECTOR_WORKBENCH_RESULT.json` and `MIR4_COMPATIBILITY_SUBJECT_LEDGER.json`. Both bind their source commit/tree when exported, record content-addressed inputs, remain developer preview, and set package, player-mutation, public-proof, support-publication, signing, and publication authority to false.

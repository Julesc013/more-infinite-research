---
title: "MIR 4.0 Whole Platform Programme"
status: current
applies_to: "4.0.0+"
audience: maintainer
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-23
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-4.0-whole-platform-consolidation
  - mir4-uppercase-f-target-presentation
  - mir4-technology-by-technology-acceptance
---
# MIR 4.0 whole platform programme

MIR 4.0.0 owns the complete MIR 4 platform source programme. The former 4.0 through 4.17 planning slots no longer reserve implementations for later source releases. Each platform area must exist as executable code with a schema, authority, verification owner, explicit maturity, cutover condition, rollback boundary, and blockers.

This consolidation does not collapse maturity. Stable player behavior remains bounded by the admitted compiler, emitter, runtime, migration, and target authorities. Preview, shadow, experimental, omitted, and blocked implementations live in the 4.0 source tree but cannot mutate player output or acquire a compatibility claim merely because their code exists.

The canonical machine authority is `.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json`; the generated inventory is [MIR 4 Whole Platform Matrix](../reference/generated/mir4-whole-platform-matrix.md).

## Target naming

Human-facing target keys use an uppercase `F`: `F210`, `F200`, `F110`, `F100`, and `F018` through `F006`. Tool boundaries continue to accept legacy lowercase input so existing scripts and immutable evidence remain usable, then normalize new output to uppercase. Historical hash-bound records are never rewritten only to change casing.

## Technology-by-technology acceptance

Compatibility is tuned by ecosystem, but admission is one exact technology at a time. The queue generator consumes the final schema-3 `TechnologyCatalog`, binds each current selection and exact design and qualification fingerprint, and emits no mutation authority. A materializing candidate then follows the existing lifecycle: quality assessment, review dossier, maintainer approval, promotion, migration when required, and exact promotion admission.

The recommended ecosystem order is Base and official mods, AAI, BZ, Krastorio 2, Space Exploration, Industrial Revolution 3 and 4, Bob, Angel, Pyanodons, then combined packs. The order is operational, not a compatibility claim. A pack is never represented by one blanket supported Boolean.

Create a queue with:

```powershell
.\tools\mir.ps1 mir4 acceptance queue --catalog <technology-catalog.json> --target F210 --ecosystem aai --output <acceptance-queue.json>
```

Then use the existing `technology quality-assessment`, `technology review-dossier`, and `technology promotion-gate` commands for each selected candidate.

## Stop boundary

This programme authorizes private implementation and verification only. Source freeze, production signing, sealing, `main` or `legacy` mutation, tags, public compatibility claims, and publication remain separately controlled.

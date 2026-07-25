---
title: "Automatic Family Balance And Scope"
status: current
applies_to: "3.1.0"
audience: maintainer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: []
superseded_by: []
---

# Automatic Family Balance And Scope

MIR 3.1.0 ships structural attachment conservatively. Confidence ranks evidence but never overrides a failed safety, ownership, target, science, lab, prerequisite, or loop gate.

## Registered Rules

| FamilyRule | Destination | Change per level | Science and prerequisites | 3.1 action |
| --- | --- | ---: | --- | --- |
| Assembling-machine manufacturing | experimental generic identity | 2% | automation, logistic, chemical, production; prerequisite frontier derived from those packs | broad opt-in creation only |
| Lab manufacturing | experimental generic identity | 2% | automation, logistic, chemical, production; prerequisite frontier derived from those packs | broad opt-in creation only |
| Furnace manufacturing | existing furnace stream | 2% | inherit target stream | safe attach |
| Inserter manufacturing | existing inserter stream | 1% | inherit target stream | safe attach |
| Loader manufacturing | existing belt stream | 1% | inherit target stream | safe attach |
| Belt/splitter/underground manufacturing | existing belt stream | 1% | inherit target stream | safe attach |
| Mining-drill manufacturing | existing mining-drill stream | 5% | inherit target stream | safe attach |
| Module manufacturing | existing module stream | 10%, 5%, 2%, then 1% | inherit target stream | safe attach by prototype tier |
| Accumulator and solar manufacturing | existing electric-energy stream | 2% | inherit target stream | safe attach |

These values intentionally match the conservative end of their destination stream tiers. Automatic recipes never receive a larger change merely because a name suggests a high tier. Owner adoption wins over MIR emission, and every emitted or adopted effect keeps exact recipe identity.

The two predeclared generic identities remain experimental in 3.1.5. Enabling research creation while retaining the reviewed-data requirement does not emit them, even if an exact compatibility pack requests generation. They remain available for explicit testing when research creation is enabled and the reviewed-data requirement is disabled. This preserves the implementation and stable IDs without presenting their current grouping, balance, or progression as accepted.

## Reviewed Deferrals

- Beacon manufacturing remains diagnostic-only: a stable destination identity and fixture-backed progression policy are not yet defined.
- Rail/support, ammunition, armor, battery, circuit, plate, and structural-component content remains under existing fixed streams and exact recipe matching. No new broad semantic FamilyRule is added in 3.1.0.
- Fluid processes, chemistry, catalyst/recovery chains, voiding, transmutation, recycling, probabilistic output, and multi-output loops remain report-only. Placeability or a high confidence score cannot make these loop-safe.
- CompatibilityPack reviewed overrides may refine only exact soft signals. Effective productivity permission, caps, parameterization, recycling, self-return, stochastic products, catalysts, exclusions, and blocking infinite owners are hard facts and cannot be overridden by pack data.

The 3.1.0 objective is complete accounting and safe attachment, not maximum automatic productivity. New automatic families require a separate stable ID decision, schema-2 rule, arbitrary-name structural fixture, negative/decoy fixture, exact modpack campaign, balance review, and migration record.

These are the currently registered family modules, not a closed compiler list or player-facing setting taxonomy. Later experimental or reviewed families plug into the same generic action, maturity, creation, authorization, plan, and emission contracts.

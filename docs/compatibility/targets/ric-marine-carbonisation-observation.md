---
title: "RIC Marine Carbonisation Development Observation"
status: current
applies_to: "MIR 4.2 development evidence only"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-09-30
supersedes: []
superseded_by: []
---

# RIC Marine Carbonisation Development Observation

This page records one exact development observation. It is not a RIC compatibility support claim, a release qualification, or publication authority. The machine-readable compatibility authority does not register a RIC public claim.

The observed profile used Factorio `2.1.20`, Real Industrial Chemistry `0.36.1`, and candidate package SHA-256 `F2D78400696EF13482E8FE8767147632AA1012AAAA88C163CE9D23D0AD87C3DF`.

In Marine mode, MIR emitted `recipe-prod-research_material_ric_coke-1` with a `+0.02` productivity effect for `ric-carbonise-marine-biomass`. The exact data-stage fixture observed the unique owner and runtime cap of three. The engine fixture researched level 1, observed a `+0.02` bonus, saved, reloaded, and observed the same level and bonus.

In Continental mode, the data-stage fixture confirmed that the Marine carbonisation technology was absent. This does not establish runtime behavior for Continental mode.

The scoped route observation withheld sixteen return-path routes. That count does not establish support for the remaining RIC recipes or systems.

The receipts are `build/tests/ric-scoping/run-20260930k-marine/result.json` and `build/tests/ric-scoping/run-20260930k-continental/result.json`. Both record source head `48e45be02774789ce5c5d24e0577b4724392c3f7`, Factorio binary SHA-256 `E4B1FDBDCC77F4C3449318CE1398493EA7A8E77A19D68BD1AC3A858D0F373B92`, RIC archive SHA-256 `AF88A7E90D57B789D7628D17C40391A27B37123F0A2C0BD8FECA7683653FF19A`, and the same MIR candidate package hash above. The Marine receipt passed data, create, and reload markers; the Continental receipt passed its data-stage marker.

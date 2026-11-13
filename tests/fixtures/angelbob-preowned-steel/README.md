---
title: "Controlled foreign steel ownership"
status: current
applies_to: "Factorio 2.1.23 AngelBob qualification fixture"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-13
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-preowned-steel-witness
---

# Controlled foreign steel ownership

This disposable data-stage fixture adds two valid Angel steel productivity effects to the existing native steel technology before MIR's final preflight. It preserves the technology identity, cost, science and other fields, and changes no recipes. It supplies the exact pre-owned condition from the reported error without pretending to reproduce the reporter's unspecified additional mods or settings.

The actual rebalance1.3.2 required-only configuration is a separate control: it initially has only the two original steel effects and also loads on MIR5.0.11. The witnessed configuration must reproduce the old guard and let the corrected package preserve the entire already-extended technology without duplication.

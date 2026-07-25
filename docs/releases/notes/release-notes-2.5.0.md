---
title: "MIR 2.5.0 Provisional Release Notes"
status: current
applies_to: "2.5.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-25
supersedes: []
superseded_by: []
---

# MIR 2.5.0 Provisional Release Notes

MIR 2.5.0 brings the C16 deterministic compatibility compiler and trusted immutable-record performance correction to Factorio 2.0. It retains safe established technologies, exact native/external ownership, fail-closed recipe-effect sanitation, previewable technology candidates, and conservative opt-in generation.

The current `2.5-P6` archive is a playtest candidate, not a release. It descends from MIR 2.4.9 baseline `7ebe93029695bbf809a15a14c6540530738a9e62` and tag `3.2.0`, projects C20 source `303de261629149af5f50bd210368e61423f1a299` at target commit `f9eb34eae9b767275a17b5e68351343042ef7532`, and has SHA-256 `98A8A8F50D8F98F8DD109E9AFF7A3C6F0097B380224A16E7065233186A4CA3BE`. It retains the exact Factorio 2.0.77 ModData/adoption capability used by published 2.4.9, adds final C20 semantics through the target profile, and prevents hard-rejected recipes from inflating automatic-family progression spans. Focused and full validation, manual review, protected qualification, sealing, and publication remain pending.

---
title: "Fresh science transition fixture"
status: draft
applies_to: "F210 published4.7.3 to MIR5 fresh science transition"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-25
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-fresh-science-transition-fixture
---

# Fresh science transition fixture

This private F210 fixture depends on the existing `mir-fixture-mir5-fresh-science-sources` 0.1.0 data-stage fixture. It reuses that fixture’s `planetary-data` source, circular alternative, seeded foreign route, and `all` policy without copying or changing any of those files.

After confirming the published defaults, `settings-updates.lua` reduces only the existing `research_science_pack_productivity` cost and time to one. It leaves growth, effects, science selection, prerequisites, and every other setting unchanged. The source level costs one pack set and its successor costs two because the unchanged growth factor remains two.

The control requires the exact F210 official closure, published MIR4.7.21003 or current MIR5.0.21000, a target with no prerequisites, and the two fixture recipe effects at `0.10`. It creates one real `biolab`, verifies that it accepts every actual target input, completes exactly one source level, and records the resulting `0.10` native bonuses for both fixture recipes. On upgrade it verifies that saved witness before starting one successor lab level, which raises both bonuses to `0.20`.

The generic `Invoke-NativeFixture.ps1` source/InputSave protocol supplies the two cold reloads. A future native orchestration must run the exact published B6EB archive first, pass its completed-save SHA256 unchanged to the exact current 3D6A archive, and preserve both archive/fixture bindings. This fixture makes no multiplayer, queue/paused-state, performance, release, or completed-native-result claim.

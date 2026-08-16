---
title: "MIR 3 Terminal Mod Portal Upload Checklist"
status: current
applies_to: "3.2.9-1.3.9"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-15
supersedes: []
superseded_by: []
---

# MIR 3 Terminal Mod Portal Upload Checklist

Upload in descending order: 3.2.9, 2.5.9, 1.9.9, 1.8.9, 1.7.9, 1.6.9, 1.5.9, 1.4.9, 1.3.9. For every row use `dist/more-infinite-research_<version>.zip` and the matching ready-to-paste text in `.mir/releases/terminal/mod-portal-descriptions/<version>.md`.

Before upload, compare the archive with `docs/releases/SHA256SUMS-MIR-3.txt`. After upload, authenticated-redownload the public file, verify archive/content hashes, bytes, entries, and package composition, run the exact-engine load smoke, and append a `Mir3TerminalPublicationReceiptV1` with channel `mod-portal`. Until those steps pass, Mod Portal status remains pending manual upload.

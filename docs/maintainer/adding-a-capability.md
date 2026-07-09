---
title: "Adding A Capability"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Adding A Capability

Start with report-first classification. Do not emit new behavior until the lane
has policy, owner checks, lab checks, loop-risk handling, stream manifest rows,
fixtures, and docs.

Update:

- `.mir/capabilities.yml`
- capability docs under `docs/capabilities/`
- fixture docs and assertions
- stream or claim manifests if generation or public wording changes

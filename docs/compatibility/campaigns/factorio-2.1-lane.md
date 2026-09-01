---
title: "Factorio 2.1 Lane"
status: current
applies_to: "3.0.0+"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-09-01
supersedes: []
superseded_by: []
---

# Factorio 2.1 Lane

The 2.1 lane is the current mainline validation target for `dev` and stable release work. Until the first official Factorio 2.1 stable release, F210 selects the latest official experimental build installed by Steam instead of pinning a long-lived patch. Every execution still binds the exact selected version and executable hash, and evidence cannot cross a patch boundary.

Every observed engine or API identity change generates the review tasks defined by `spec/engines/mir4-factorio-2.1-experimental-channel-v1.json`. The operator procedure and stable-transition stop condition are in [Factorio 2.1 Experimental Channel Policy](../../maintainer/factorio-2.1-experimental-channel.md).

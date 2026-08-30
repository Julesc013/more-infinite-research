---
title: "MIR 4 Developer Documentation"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-developer-documentation-navigation
---

# MIR 4 developer documentation

MIR 4.0 ships stable player products and separate package-excluded developer previews. The previews are executable and conforming, but they cannot mutate player prototypes, replace the terminal emitter, sign releases, or create public support claims.

Start with [Your first extension](first-extension.md). Continue with the [compatibility cookbook](compatibility-cookbook.md), [fragment reference](mep-fragment-reference.md), and [publishing guide](publishing-an-extension.md).

Contract authors should read [API versioning](api-versioning.md), [canonicalization](canonicalization.md), [diagnostics](diagnostics.md), and [environment locks](environment-locks.md). Read-only analysis is covered by [Inspector](inspector.md) and [ProcessIR](processir.md).

All examples are offline and use relative paths. The preview archive is never a Factorio mod.

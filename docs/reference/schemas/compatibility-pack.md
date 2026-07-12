---
title: "CompatibilityPack Schema"
status: current
applies_to: "post-3.1 dev"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# CompatibilityPack Schema

A schema-1 `CompatibilityPack` is a data-only policy packet. It may declare selectors, guarded competing-owner patterns, expected decision classes, and claim metadata. It cannot contain functions or prototype mutation callbacks.

External fixtures may register a pack through the `more-infinite-research-compatibility-pack` `mod-data` prototype. MIR validates and consumes that packet during final planning. This keeps fixture-only mod identities and policies out of the production profile table while exercising the same pack schema a reviewed modpack policy would use.

Compatibility packs never create technologies. They may only influence a policy decision that is still subject to owner, effect identity, science, graph, plan, and emission validation.


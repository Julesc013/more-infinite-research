---
title: "Generated ID Reference"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: ["schemas/stream-manifest.md"]
superseded_by: []
---

# Generated ID Reference

## Predeclared Automatic Family IDs

MIR 2.4.0 predeclares `mir-auto-prod-manufacturing-assembling-machine-1` and `mir-auto-prod-manufacturing-lab-1`. These IDs derive from stable semantic family names, never from mod or recipe names. Both remain experimental: they are absent in the default attachment-only policy and in reviewed-data creation mode. The explicit broad opt-in policy may emit them after whole-plan validation. Predeclaration stabilizes identity; it does not assert that balance, grouping, or progression is accepted.

Generated recipe-productivity technologies use stable names:

```text
recipe-prod-<stream-key>-1
```

Generated base-technology continuations use the vanilla technology chain name and next level:

```text
<vanilla-technology-name>-<next-level>
```

Released generated IDs are save-facing API. Renames, removals, or stream target changes require migration review and release notes.

The machine-readable generated stream record remains `prototypes/mir/streams/generated_stream_manifest.json`, routed through `.mir/streams.yml`.

Every stream key in the current legacy stream tables must have a manifest row. Most rows use the emitted `recipe-prod-<stream-key>-1` technology name as the manifest key. Compatibility policy streams may use a clearer stable `mir-prod-*` manifest key, but they still record the emitted Factorio technology name in `generated_technology`.

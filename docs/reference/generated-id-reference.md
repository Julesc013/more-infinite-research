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

Generated recipe-productivity technologies use stable names:

```text
recipe-prod-<stream-key>-1
```

Generated base-technology continuations use the vanilla technology chain name
and next level:

```text
<vanilla-technology-name>-<next-level>
```

Released generated IDs are save-facing API. Renames, removals, or stream target
changes require migration review and release notes.

The machine-readable generated stream record remains
`prototypes/planner/generated-stream-manifest.json`, routed through
`.mir/streams.yml`.

Every stream key in the current legacy stream tables must have a manifest row.
Most rows use the emitted `recipe-prod-<stream-key>-1` technology name as the
manifest key. Compatibility policy streams may use a clearer stable `mir-prod-*`
manifest key, but they still record the emitted Factorio technology name in
`generated_technology`.

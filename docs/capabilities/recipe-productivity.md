---
title: "Recipe Productivity Capability"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Recipe Productivity Capability

Recipe productivity is the capability lane that creates
`change-recipe-productivity` effects for validated recipe families.

## Gates

- Target recipes must exist and be visible unless the stream explicitly opts in.
- Recipe productivity must be allowed by the prototype.
- The recipe must not be owned by a conflicting infinite technology unless an
  exact replacement or adoption policy passes.
- Science ingredients must be lab-compatible.
- Loop-risk and recovery signals must be rejected or explicitly allowed.
- The generated stream must have a stable manifest row.

## Related Docs

- [Stream manifest schema](../reference/schemas/stream-manifest.md)
- [Generated ID reference](../reference/generated-id-reference.md)
- [Policy overlays](../compatibility/policy-overlays.md)

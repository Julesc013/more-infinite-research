---
title: "MIR 4 maintainer guide"
status: current
applies_to: "MIR 4.x"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-31
supersedes: []
superseded_by: []
generated_from: []
---

# MIR 4 maintainer guide

MIR 4 keeps `main` as latest stable, `dev` as next-minor or next-major integration, and `release/4.0` as the maintained 4.0.x correction lane. Start work from the lane named by the [operating programme](../releases/mir4-post-4.0-roadmap.md), use one finding identity across every applicable lane, and qualify each affected target independently.

## Common work

- [Contributing](../../CONTRIBUTING.md)
- [Branch operating model](../releases/mir4-post-4.0-roadmap.md#stable-maintenance-and-next-release-development)
- [Backporting](backporting.md)
- [Documentation governance](documentation-governance.md)
- [Fixture workflow](fixture-workflow.md)
- [Settings governance](settings-governance.md)
- [Artifact retention](artifact-retention.md)
- [Authority map](mir4-authority-map.md)

The [MIR 4.x operating programme](../releases/mir4-post-4.0-roadmap.md) defines fixed-point order. Change fragments under `changes/unreleased/` own release-change facts. The package boundary still includes the root README; do not edit it until M41-05B admits the package-documentation cutover with target-local proof.

For source layout and dependency boundaries, use [module boundaries](../architecture/module-boundaries.md). Do not begin broad Lua movement until package characterization, the target materializer, parity, rollback, and the package-source cutover are accepted.

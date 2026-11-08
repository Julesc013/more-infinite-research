---
title: "MIR 5.0.10 beta release notes"
status: current
applies_to: "MIR 5.0.10 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-08
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-510-release-notes
---

Fixes worker robot cargo research conflicts and Space Is Fake science requirements.

- Preserve other mods' finite cargo research and continue after its final level, including WorkerRobotCargoSizeResearch; retain an existing infinite continuation.
- Keep MIR research free of retired white science with Space Is Fake, including expanded science policies.
- Improve saved bonus-history error details while retaining the previous research-cost multiplier fix.
- Back up your save and matching mods before updating. Changing cargo-research providers on an existing MIR save may be refused when previous ownership cannot be established; restore the previous selection and original save in that case.

[Installation and support](https://github.com/Julesc013/more-infinite-research/blob/v5.0.10/docs/support.md).

---
title: "Asset Sources"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-10
supersedes: []
superseded_by: []
---
# Asset Sources

This file records local image assets packaged by More Infinite Research. Generated
technology icons should normally borrow active Factorio prototype icons at data
stage instead of copying Wube asset files into this mod.

| Path | Source | Redistribution note |
| --- | --- | --- |
| `thumbnail.png` | More Infinite Research package thumbnail. | Project-owned presentation asset; not copied from Space Age. |

Policy:

- Do not copy original Space Age PNGs or other DLC asset files into this mod as
  base-only fallbacks.
- Direct official DLC icon references such as `__space-age__` or
  `__elevated-rails__` are allowed only as prototype paths gated by
  `mir-use-installed-space-age-icons`; they are not packaged assets.
- Target-line fallback overlays should reference assets already present in the
  active Factorio install. Prefer the same high-resolution stock core
  technology badge layers used by the target game's own technology helpers,
  such as `__core__/graphics/icons/technology/constants/*`, for technology
  tile overlays. The smaller
  `__core__/graphics/icons/technology/effect-constant/*` sprites are effect
  row utility art and should not be used as technology tile badges unless a
  target line has no high-resolution equivalent and the substitution is
  documented.
- Any future MIR-owned or third-party local art must be added to this table with
  an explicit source and redistribution note before package validation can pass.

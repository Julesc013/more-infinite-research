---
title: "Troubleshooting"
status: current
applies_to: "3.0.0+"
audience: player
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Troubleshooting

If a technology is missing:

1. Enable `mir-debug-generation-report`.
2. Restart or load a controlled test map.
3. Search `factorio-current.log` for the stream key.
4. Check for `skipped`, `no_matching_recipes`, `missing required`, or
   `no_lab_compatible_science`.

If a recipe did not receive productivity:

1. Enable `mir-debug-recipe-matches`.
2. Confirm the recipe outputs a target item or fluid.
3. Confirm the recipe is visible and not recycling unless the stream opts in.
4. Confirm the recipe exists before MIR reaches `data-final-fixes.lua`.

# Maintainer Guide

Updated: 2026-07-07

This guide describes the intended 3.0 workflow for adding compatibility without
copying generator logic into per-mod files.

## Adding A New Capability

1. Define the capability ID and schema version.
2. Add structural discovery from facts.
3. Add classification with decomposed confidence.
4. Add proposal logic that creates reviewable candidate output.
5. Add validation gates for owner, science, lab, cap, loop risk, and policy.
6. Add report-only diagnostics first.
7. Add negative fixtures before auto-emission.
8. Add a manifest row before any generated stream ships.
9. Add compatibility claim text only after fixture proof.

## Adding A Policy Overlay

1. Prefer exact IDs for the first slice.
2. Use structural selectors only when the fact model proves them.
3. Add deny-risk flags.
4. Derive science from unlocks where possible.
5. Require lab compatibility.
6. Preserve external owners unless exact policy proves cleanup.
7. Add a claim manifest entry.
8. Add fixture expectations.
9. Run policy linting.

## Adding A Real Mod Fixture

1. Record mod name, version, source, and target Factorio line.
2. Capture upstream advertised Factorio versions separately from tested lines.
3. Add expected generated streams.
4. Add expected diagnostic-only rows.
5. Add expected rejected recipes.
6. Add expected lab/science matrix behavior.
7. Add expected cap diagnostics.
8. Add package hygiene expectations.

## Triage Rule

Convert every bug report into one of:

- a negative fixture;
- a policy overlay correction;
- a classifier correction;
- a claim wording correction;
- a migration rule;
- a rejected/deferred scope note.

Do not fix compatibility bugs by adding unexplained `if mods[...]` generation
branches.


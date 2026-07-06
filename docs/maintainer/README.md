# Maintainer Guide

Updated: 2026-07-07

This guide describes the intended 3.0 workflow for adding compatibility without
copying generator logic into per-mod files.

Use `docs/notes/3.0.0-repository-structure.md` for where new files belong.
New shipped Lua should go under `prototypes/mir/` unless it is a thin Factorio
root entrypoint, locale, migration, graphics asset, or a temporary legacy shim.
Development-only docs, scripts, fixtures, tests, build output, task ledgers, and
release archives stay outside the shipped package.

## Adding Or Moving Shipped Lua

1. Keep the root Factorio file as a stage wrapper.
2. Put Factorio global access behind `prototypes/mir/platform/`.
3. Put plain compiler records under `prototypes/mir/domain/`.
4. Put indexing, graphing, classification, policy, capability, planning,
   emission, and reporting code in their matching layer.
5. Put compatibility rules in `prototypes/mir/compatibility/` as declarative
   policy overlays.
6. Keep old paths as `prototypes/mir/legacy/` shims when backporting would
   otherwise become noisy.
7. Do not add new business logic to legacy shims.

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

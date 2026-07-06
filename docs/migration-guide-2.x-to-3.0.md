# Migration Guide: 2.x To 3.0

Updated: 2026-07-07

This guide is a planning document until `3.0.0` is implemented. Its purpose is
to keep the 3.0 architecture compatible with existing saves and existing player
expectations.

## Version Line Change

After the transition:

- `3.x.x` targets Factorio `2.1`;
- `2.x.x` targets Factorio `2.0` starting at `2.5.0`;
- `1.9.3+` targets Factorio `1.1`;
- `1.8.x` targets Factorio `1.0`;
- `1.7.x` through `1.3.x` target Factorio `0.17` through `0.13`;
- `0.12.x` through `0.6.x` target Factorio `0.12` through `0.6` as archive
  or museum lines;
- `1.9.0` through `1.9.2` remain historical Factorio `2.0` transition ports.

See `docs/notes/target-line-versioning-and-backports.md`.

## User-Facing Behavior

3.0 should preserve existing generated technology IDs unless a tested migration
exists. The architecture may change internally, but a player should not lose
research progress because a stream moved behind `StreamSpec`.

Expected visible changes:

- diagnostics become more structured;
- compatibility claims become narrower and more evidence-backed;
- some unknown or risky modded recipes may appear in reports instead of being
  silently ignored;
- settings may gain capability-specific wording only when the capability emits
  real behavior.

Non-goals:

- no automatic cap mutation;
- no automatic beacon/module/recycler productivity;
- no broad "all recipes" generator;
- no broad external owner replacement.

## Maintainer Migration Work

When moving a stream into the 3.0 compiler:

1. Add or confirm a manifest row for the current generated technology.
2. Preserve the generated technology ID.
3. Add `DecisionRecord` expectations.
4. Add `StreamSpec` expectations.
5. Confirm science/lab compatibility.
6. Confirm duplicate-owner policy.
7. Confirm loop-risk denial.
8. Run report diffing before and after the move.
9. Add a migration only if a released ID changes.

## Save Compatibility

Released generated IDs are append-only unless a migration handles the change.
If a stream target list changes, the old generated technology should remain
stable unless the release notes and manifest explain the migration behavior.

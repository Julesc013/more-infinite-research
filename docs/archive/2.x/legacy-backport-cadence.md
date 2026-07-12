---
title: "Legacy Backport Cadence"
status: archived
applies_to: "1.x-2.x"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: ["../../releases/README.md"]
---
# Legacy Backport Cadence

Updated: 2026-07-07

This note records the intended compatibility backport ladder for More Infinite
Research across older Factorio lines. It is a release-planning note, not a
feature-parity promise. Each release still needs an exact tested current-line
source point, target-line metadata, explicit guards for unsupported APIs, a
package build, and target-line validation before public claims are made.

This is the current maintainer-authorized plan. It is intentionally tentative:
dates, target ordering, exact source snapshots, and even individual target-line
releases may move if Factorio `2.1`, the Mod Portal, validation binaries, or MIR
itself make a different order safer. Changes should be recorded in this note,
`docs/roadmap.md`, and root `todo.md` instead of being left as chat-only plans.
The locked post-`2.2.0` target-line policy and `tmp/2.0` workflow live in
`docs/notes/target-line-versioning-and-backports.md`.

## Current-Line Cadence

From 2026-07-06 through the end of December 2026, the intended current-line
cadence is one Factorio `2.1` More Infinite Research update each week when there
is a safe, validated package to ship.

Weekly does not mean "ship broken work." A weekly update may be a small bug fix,
compatibility profile, validation/tooling improvement, documentation correction,
or low-risk feature slice. If a week has no validated release candidate, record
the skipped release reason and continue the cadence the following week.

## Factorio 2.1 Celebration Backport Window

To celebrate the Factorio `2.1` release, the intended backport campaign is one
older-line compatibility release per day from the week preceding the Factorio
`2.1` release through the week following it.

That daily campaign should use the planned releases below as the target pool.
The exact day-by-day assignment can change once the real Factorio `2.1` release
date and available target binaries are known. A day can be skipped rather than
publishing an unvalidated or misleading archive; if that happens, document the
skip and resume with the next safest target.

## Snapshot Labels

Use these labels when planning, tagging, release-note writing, and validation:

| Snapshot label | Meaning |
| --- | --- |
| Week-before-2.1-release snapshot | Latest tested canonical MIR source point one week before the Factorio `2.1` release. |
| 2.1-release snapshot | Latest tested canonical MIR source point at the Factorio `2.1` release. |
| 2.1-stable end-of-year snapshot | Latest tested canonical MIR source point for the Factorio `2.1` stable/end-of-year support sweep. |
| 3.0-architecture source point | Tested MIR `3.x.x` compiler-architecture source point used for post-transition target-line ports. |

For all rows below, "backport" or "port" means a best-compatible subset of the
selected source snapshot. If the target Factorio line cannot support a feature,
remove, guard, or reconstruct that surface and document the exclusion in the
release notes.

## Planned Releases

| MIR release | Target Factorio line | Support class | Timing | Source snapshot |
| --- | --- | --- | --- | --- |
| `1.9.2` | `2.0.x` | Transition backport | Immediate | Tested `2.2.0` source point |
| `2.3.0` | `2.0.x` | Maintained `2.0` backport | After `3.0.0` is stable | 3.0-architecture source point |
| `1.9.3` | `1.1.x` | Compatibility port | After `2.3.0` or explicit maintainer gate | 3.0-architecture source point, reduced by capability |
| `1.8.0` | `0.18.x` bridge | Bridge archive | After `1.9.3`; must load in `0.18` and the same zip in `1.0` | Validated `1.9.3` source point, reduced by `0.18` binary proof |
| `1.8.1` | `1.0.x` | Compatibility port | Immediately after the `0.18` bridge proof | `1.8.0` bridge proof or `1.9.3` plus bridge lessons |
| `1.7.0` | `0.17.x` | Reduced native-infinite | After target binary proof | Reduced native-infinite source shape |
| `1.6.0` | `0.16.x` | Old-science native-infinite | After target binary proof | Old-science native-infinite source shape |
| `1.5.0` | `0.15.x` | Minimal native-infinite | After target binary proof | Minimal native-infinite source shape |
| `1.4.0` | `0.14.x` | Archive finite reconstruction | After target binary proof | Finite-ladder reconstruction |
| `1.3.0` | `0.13.x` | Archive finite reconstruction | After target binary proof | Finite-ladder reconstruction |
| `0.12.0` | `0.12.x` | Archive experiment | After target binary proof | Archive reconstruction |
| `0.11.0` | `0.11.x` | Museum/discovery | After target binary and base-file discovery | Museum reconstruction |
| `0.10.0` | `0.10.x` | Museum/discovery | After target binary and base-file discovery | Museum reconstruction |
| `0.9.0` | `0.9.x` | Museum/discovery | After target binary and base-file discovery | Museum reconstruction |
| `0.8.0` | `0.8.x` | Museum/discovery | After target binary and base-file discovery | Museum reconstruction |
| `0.7.0` | `0.7.x` | Museum/discovery | After target binary and base-file discovery | Museum reconstruction |
| `0.6.0` | `0.6.x` | Extreme museum | After target binary and base-file discovery | Minimal commemorative reconstruction |

The previous `1.9.7` / `1.9.8` / `1.9.9` Factorio `2.0` ladder and the
previous `1.8.x` / `1.7.x` compressed older-line ladder are superseded by this
locked line mapping unless the maintainer explicitly reopens the versioning
policy.

## Execution Rules

- Keep current Factorio `2.1` development as the primary line.
- Treat weekly current-line updates through December 2026 as a cadence goal,
  not permission to bypass validation.
- Treat the week-before through week-after Factorio `2.1` daily backport burst
  as a celebration campaign, not permission to claim parity on older APIs.
- Record the exact MIR `2.x.x` tag or commit selected for each snapshot before
  starting a backport.
- Use target-specific branches; do not rebuild old lines commit-by-commit from
  historical MIR release history unless a target line cannot accept the current
  source shape.
- Set `info.json` version, `factorio_version`, and dependency floors for the
  target Factorio line.
- Remove or guard unsupported current-line surfaces, especially Factorio
  `2.1`-only technology modifiers, prototype fields, and runtime events.
- Treat Factorio `1.1` and older lines as higher-risk manual ports. Expect
  larger data-lifecycle, prototype, locale, and migration differences than the
  Factorio `2.0` legacy line.
- Run static validation, package validation, and a target Factorio binary load
  check when a compatible binary is available.
- If a target binary is not available, release notes must say which validation
  was not run.
- Do not claim full feature parity for any older line unless that exact target
  line has been validated with the claimed features enabled.

## Post-Transition Note

After the `1.9.2` Factorio `2.0` transition backport, the target-line scheme is
locked. `1.9.0` through `1.9.2` remain historical Factorio `2.0` transition
archives, but `1.9.3+` is reserved for Factorio `1.1`; Factorio `2.0` moves to
`2.x.x` starting at `2.3.0`; Factorio `2.1` moves to `3.x.x` starting at
`3.0.0`; and `0.12.x` through `0.6.x` map directly to Factorio `0.12` through
`0.6` as archive or museum lines.

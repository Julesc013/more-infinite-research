# Legacy Backport Cadence

Updated: 2026-07-06

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
| Week-before-2.1-release snapshot | Latest tested MIR `2.x.x` source point one week before the Factorio `2.1` release. |
| 2.1-release snapshot | Latest tested MIR `2.x.x` source point at the Factorio `2.1` release. |
| 2.1-stable end-of-year snapshot | Latest tested MIR `2.x.x` source point for the Factorio `2.1` stable/end-of-year support sweep. |

For all rows below, "backport" means a best-compatible subset of the selected
`2.x.x` source snapshot. If the target Factorio line cannot support a feature,
remove or guard that surface and document the exclusion in the release notes.

## Planned Releases

| MIR release | Target Factorio line | Timing | Source snapshot |
| --- | --- | --- | --- |
| `1.9.9` | `2.0.x` | End of year | 2.1-stable end-of-year snapshot |
| `1.9.8` | `2.0.x` | At Factorio `2.1` release | 2.1-release snapshot |
| `1.9.7` | `2.0.x` | One week before Factorio `2.1` release | Week-before-2.1-release snapshot |
| `1.8.9` | `1.1.x` | End of year | 2.1-stable end-of-year snapshot |
| `1.8.8` | `1.1.x` | One week before Factorio `2.1` release | Week-before-2.1-release snapshot |
| `1.8.7` | `1.0.x` | End of year | 2.1-stable end-of-year snapshot |
| `1.8.6` | `1.0.x` | One week before Factorio `2.1` release | Week-before-2.1-release snapshot |
| `1.8.5` | `0.17.x` | At Factorio `2.1` release | 2.1-release snapshot |
| `1.8.4` | `0.17.x` | One week before Factorio `2.1` release | Week-before-2.1-release snapshot |
| `1.8.3` | `0.16.x` | At Factorio `2.1` release | 2.1-release snapshot |
| `1.8.2` | `0.16.x` | One week before Factorio `2.1` release | Week-before-2.1-release snapshot |
| `1.8.1` | `0.15.x` | At Factorio `2.1` release | 2.1-release snapshot |
| `1.8.0` | `0.15.x` | One week before Factorio `2.1` release | Week-before-2.1-release snapshot |
| `1.7.8` | `0.14.x` | After Factorio `2.1` release | Week-before-2.1-release snapshot |
| `1.7.7` | `0.13.x` | After Factorio `2.1` release | Week-before-2.1-release snapshot |
| `1.7.6` | `0.12.x` | After Factorio `2.1` release | Week-before-2.1-release snapshot |
| `1.7.5` | `0.11.x` | After Factorio `2.1` release | Week-before-2.1-release snapshot |
| `1.7.4` | `0.10.x` | After Factorio `2.1` release | Week-before-2.1-release snapshot |
| `1.7.3` | `0.9.x` | After Factorio `2.1` release | Week-before-2.1-release snapshot |
| `1.7.2` | `0.8.x` | After Factorio `2.1` release | Week-before-2.1-release snapshot |
| `1.7.1` | `0.7.x` | After Factorio `2.1` release | Week-before-2.1-release snapshot |
| `1.7.0` | `0.6.x` | After Factorio `2.1` release | Week-before-2.1-release snapshot |

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

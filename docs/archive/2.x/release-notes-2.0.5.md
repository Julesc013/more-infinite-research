---
title: "More Infinite Research 2.0.5 Release Notes"
status: archived
applies_to: "1.x-2.x"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: ["../../releases/README.md"]
---
# More Infinite Research 2.0.5 Release Notes

This is the short, player-facing release summary for the `2.0.5` mod portal release notes. It is derived from `changelog.txt`; the changelog remains the detailed source of truth.

## Headline

`2.0.5` is a quick feedback patch for the Factorio `2.1` line. It focuses on bug fixes, better generated technology ownership, clearer icons and settings, broader compatibility checks, and default-off experimental Space Age agriculture/spoilage research.

## What Changed

- Electric Shooting Speed now covers Space Age Tesla weapons and Tesla turrets, while still covering vanilla discharge-defense-style electric weapons.
- Electric, Tesla, and flamethrower shooting-speed effects now have proper descriptions.
- Electric Shooting Speed now uses appropriate electric weapon art and the correct speed badge.
- Tank cannon fire rate should no longer be reduced by MIR's weapon-speed overlap handling.
- Quality is now a hidden optional load-order dependency, so Module productivity can see quality module recipes when Quality is active.
- Mining drill productivity now covers Omega Drill style outputs such as `omega-drill` and `omega-tau`, plus broader visible modded drill recipes.
- Space Age's vanilla processing unit, low density structure, plastic, rocket fuel, and research productivity technologies stay authoritative instead of receiving parallel MIR duplicates.
- Heavy ammunition productivity was renamed to Cannon shell productivity for clearer player-facing scope.
- Cannon shell productivity now covers cannon shells, artillery shells, railgun ammo, and compatible modded shell/ammo recipes, but not artillery or railgun buildings.
- Character inventory slots now also grants logistic trash slots. Existing progress from the old generated trash-slot technology is migrated into the combined technology.
- Character reach now uses the pickaxe/mining-speed-style icon.
- Processing Unit, Rocket Fuel, Wall, Science pack, Research productivity, Agricultural Growth Speed, and several speed/productivity technologies now use better source icons and matching MIR badges.
- Base-game saves without Space Age can now get a MIR Research productivity technology using Factorio's native lab productivity modifier. Space Age keeps vanilla Research productivity.

## Settings And UX

- Startup setting names and tooltips were cleaned up to be more Factorio-style and easier to scan.
- Default-disabled technology settings now appear before the enabled technology list, so opt-in features are easier to find.
- Technology tunables now sort alphabetically by player-facing technology name.
- Diagnostics settings now say `Log...` instead of sounding like HUD overlays.
- Dropdown options now have descriptions.
- Experimental/sandbox settings now warn clearly when they are disabled by default or balance-sensitive.
- The README now explains common settings setups and exactly what `0` means.

## Experimental Candidates

`2.0.5` includes two disabled-by-default Space Age scripted research candidates:

- Spoilage Preservation.
- Agricultural Growth Speed.

They are opt-in for testing. They are event-driven and avoid broad per-tick scans, but existing spoilable stack behavior, reversal, disabling, multi-force behavior, and large real-save behavior still need manual validation before stronger claims or default enablement.

## Compatibility And Validation

- Added broader automated validation for base-only and Space Age generation.
- Added checks that recipe productivity has a single infinite owner.
- Added checks that vanilla numbered technology continuations extend serially instead of duplicating or replacing vanilla levels.
- Added fixture coverage for Quality module productivity, Omega Drill style recipes, Space Age duplicate productivity skips, icon ownership, settings coverage, cargo diagnostics, and weapon speed safety.
- Added branch-aware guardrails for the planned Factorio `2.0` legacy backport.
- Added package/source parity validation so stale release zips are caught before publishing.

## Known Notes

- Recipe productivity still respects Factorio's normal productivity cap.
- Scripted spoilage/agriculture research is disabled by default.
- Real settings presets are still planned for a later release because preset override behavior needs a deliberate design.
- A Factorio `2.0` legacy backport is planned after the tested `2.0.5` source point is released.

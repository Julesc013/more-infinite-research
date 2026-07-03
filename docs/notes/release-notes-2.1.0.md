# More Infinite Research 2.1.0 Release Notes

This is the short, player-facing release summary for the `2.1.0` mod portal release notes. It is derived from `changelog.txt`; the changelog remains the detailed source of truth.

## Headline

`2.1.0` is the first larger Factorio `2.1` feature wave after the `2.0.5` quick patch. It focuses on simpler settings control, safer icon selection, fluid-output productivity, an opt-in pipeline extent setting, and more conservative duplicate-productivity compatibility.

## What Changed

- Removed the planned settings modes and per-technology enable policy dropdowns before release. Per-technology enable checkboxes are the single enablement path.
- Scripted Spoilage Preservation and Agricultural Growth Speed now follow the same enable checkbox rules as data-stage generated technologies.
- Spoilage Preservation now includes Space science in its research cost alongside agricultural and cryogenic science.
- Agricultural Growth Speed now includes electromagnetic and cryogenic science alongside agricultural science.
- Rocket Shooting Speed and Cannon Shooting Speed now use electromagnetic science instead of agricultural science.
- Added better icon source resolution. MIR can prefer loaded official DLC art, use base-game fallbacks, or opt into installed-but-disabled official DLC icon files when the user explicitly enables that option.
- Added fluid-output productivity research for oil processing, oil cracking, lubricant, sulfuric acid, acid neutralization, thruster fuel, and thruster oxidizer recipes where those recipes exist.
- Oil processing, Oil cracking, Lubricant, and Sulfuric acid productivity now use cryogenic, agricultural, electromagnetic, and metallurgic science respectively instead of sharing Space science as the extra pack.
- Oil cracking productivity uses oil processing technology art. Sulfuric acid productivity uses sulfuric acid fluid art and also covers acid neutralization when that recipe exists.
- Split the old Stone product productivity line into Landfill productivity, Artificial soil productivity, and Molten metals productivity. Artificial soil productivity now includes Space science in its research cost.
- Lithium productivity now also covers lithium from brine at a lower per-level rate.
- Added Carbon productivity and Ice productivity for Space Age asteroid-crushing and compatible output recipes. Carbon productivity also covers burnt spoilage at `+5%` and coal synthesis at `+2%`.
- Added Bacteria cultivation productivity for Space Age iron and copper bacteria cultivation recipes.
- Bacteria cultivation productivity and Breeding productivity now include cryogenic science alongside agricultural science.
- Added an opt-in startup-only pipeline extent multiplier dropdown. The default `100%` setting leaves prototypes unchanged.
- Added conservative adoption of mod-added recipes into existing vanilla Space Age productivity families for processing units, plastic bars, low density structures, and rocket fuel.
- Improved replacement of known Plates n Circuit Productivity technologies so MIR can generate the covered replacement effects before removing the competing technologies.

## Compatibility And Validation

- Added fixture validation for checkbox enablement, scripted runtime routing, icon source selection, fluid-output recipe ownership, and pipeline extent scaling.
- Base-only validation confirms generated icons do not use direct official DLC asset paths unless the installed official DLC icon opt-in is enabled.
- Fluid productivity validation confirms the implemented fluid recipe streams have exact recipe ownership and avoid duplicate infinite owners.
- Pipeline validation confirms the default `100%` setting does not run the prototype pass, and that explicit non-default dropdown values mutate representative fluid boxes.
- Vanilla-family adoption validation covers exact owner skips, prepatched owner skips, mixed owner fallback, existing-save effect refresh, and productivity-disallowed recipes.
- Plates n Circuit Productivity validation covers full replacement and partial-coverage behavior.
- Existing Stone product productivity progress migrates into the new Landfill productivity line as the closest successor. Artificial soil productivity and Molten metals productivity are new separate lines.

## Known Notes

- Recipe productivity still respects Factorio's normal productivity cap.
- Spoilage Preservation and Agricultural Growth Speed remain disabled by default and should be treated as experimental.
- Existing planted crops are not globally rescanned by Agricultural Growth Speed.
- The pipeline extent multiplier is a startup setting, not research. Non-default values should be tested carefully in large or heavily modded fluid networks.
- Broad native modifier overlap policy, existing agricultural plant rescale, and high-throughput pump work remain deferred unless separately implemented and validated.

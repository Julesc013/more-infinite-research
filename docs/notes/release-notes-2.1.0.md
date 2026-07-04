# More Infinite Research 2.1.0 Release Notes

This is the short, player-facing release summary for the `2.1.0` mod portal release notes. It is derived from `changelog.txt`; the changelog remains the detailed source of truth.

## Headline

`2.1.0` is the first larger Factorio `2.1` feature wave after the `2.0.5` quick patch. It focuses on Space Age productivity coverage, safer icons, fluid-output productivity, a startup pipeline-extent option, and more conservative duplicate-productivity compatibility.

## What Changed

- Spoilage Preservation now uses agricultural, cryogenic, and Space science.
- Agricultural Growth Speed now uses agricultural, electromagnetic, and cryogenic science.
- Rocket Shooting Speed and Cannon Shooting Speed now use electromagnetic science.
- Cargo Bay Unloading Distance now uses the unloading bay technology art.
- Cargo Landing Pad Count now uses Space platform technology art.
- Added fluid-output productivity for oil processing, oil cracking, lubricant, sulfuric acid, acid neutralization, and thruster recipes where those recipes exist.
- Fluid-output productivity now uses more specific science packs: cryogenic for oil processing, agricultural for cracking, electromagnetic for lubricant, and metallurgic for sulfuric acid.
- Split the old Stone Product Productivity line into Landfill Productivity, Artificial Soil Productivity, and Molten Metals Productivity.
- Landfill Productivity gives `+10%` landfill and `+5%` foundation productivity.
- Artificial Soil Productivity gives `+10%` artificial soil and `+5%` overgrowth soil productivity, with Space science.
- Molten Metals Productivity gives `+10%` lava metal and `+5%` ore melting productivity.
- Lithium Productivity now also covers lithium from brine at a lower per-level rate.
- Added Carbon Productivity and Ice Productivity for Space Age asteroid-crushing and compatible output recipes.
- Carbon Productivity also covers burnt spoilage at `+5%` and coal synthesis at `+2%`.
- Added Bacteria Cultivation Productivity for Space Age iron and copper bacteria cultivation recipes.
- Bacteria Cultivation Productivity and Breeding Productivity now include cryogenic science.
- Added an opt-in startup-only pipeline extent multiplier. The default `100%` setting leaves prototypes unchanged.

## Compatibility

- MIR can adopt safe mod-added recipes into existing vanilla Space Age productivity families for processing units, plastic bars, low density structures, and rocket fuel.
- Known Plates n Circuit Productivity technologies are replaced only when MIR fully matches the covered recipes and productivity values.
- Partial, mismatched, or externally blocked competing productivity technologies are left in place.
- Unknown external recipe-productivity owners make MIR suppress the matching effect instead of creating duplicate ownership.
- Elevated Rails and Quality remain hidden load-order dependencies without separate visible requirements.

## Migration

- Existing Stone Product Productivity progress migrates into the new Landfill Productivity line.
- Artificial Soil Productivity and Molten Metals Productivity are new separate research lines.

## Known Notes

- Recipe productivity still respects Factorio's normal productivity cap.
- Spoilage Preservation and Agricultural Growth Speed remain disabled by default and should be treated as experimental.
- Existing planted crops are not globally rescanned by Agricultural Growth Speed.
- The pipeline extent multiplier is a startup setting, not research. Non-default values should be tested carefully in large or heavily modded fluid networks.

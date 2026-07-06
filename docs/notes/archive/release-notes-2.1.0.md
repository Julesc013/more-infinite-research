# More Infinite Research 2.1.0 Release Notes

This is the short, player-facing release summary for the `2.1.0` mod portal release notes. It is derived from `changelog.txt`; the changelog remains the detailed source of truth.

## Summary

`2.1.0` is the first larger Factorio `2.1` feature wave after the `2.0.5` quick patch. It focuses on Space Age productivity coverage, fluid productivity, a startup pipeline-extent option, and more conservative duplicate-productivity compatibility.

## Changed

- Added fluid productivity research for oil processing, cracking, lubricant, sulfuric acid, acid neutralization, and thrusters.
- Added Space Age material productivity research for landfill, artificial soil, molten metals, carbon, ice, and bacteria.
- Added lithium-from-brine productivity coverage to Lithium Productivity.
- Rail Productivity now covers Elevated Rails supports and ramps when Elevated Rails is active.
- Split the old Stone Product Productivity line into Landfill, Artificial Soil, and Molten Metals research lines.
- Updated Space Age science-pack requirements for fluid, agriculture, bacteria, breeding, and shooting-speed research.
- Updated cargo logistics technology icons to better match their Space Age unlocks.
- Added an opt-in startup-only pipeline extent multiplier. The default `100%` setting leaves prototypes unchanged.

## Compatibility

- MIR can adopt safe mod-added recipes into existing vanilla Space Age productivity families for processing units, plastic bars, low density structures, and rocket fuel.
- Existing saves refresh technology effects when adopted vanilla-family recipe signatures change.
- Known Plates n Circuit Productivity technologies are replaced only when MIR fully matches the covered recipes and productivity values.
- Partial, mismatched, or externally blocked competing productivity technologies are left in place.
- Unknown external recipe-productivity owners make MIR suppress the matching effect instead of creating duplicate ownership.
- Elevated Rails and Quality remain hidden load-order dependencies without separate visible requirements.

## Migration

- Existing Stone Product Productivity progress migrates into the new Landfill Productivity line.
- Artificial Soil Productivity and Molten Metals Productivity are new separate research lines.

## Notes

- Recipe productivity still respects Factorio's normal productivity cap.
- Spoilage Preservation and Agricultural Growth Speed remain disabled by default and should be treated as experimental.
- Existing planted crops are not globally rescanned by Agricultural Growth Speed.
- The pipeline extent multiplier is a startup setting, not research. Non-default values should be tested carefully in large or heavily modded fluid networks.

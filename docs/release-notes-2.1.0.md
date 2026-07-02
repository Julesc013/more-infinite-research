# More Infinite Research 2.1.0 Release Notes

This is the short, player-facing release summary for the `2.1.0` mod portal release notes. It is derived from `changelog.txt`; the changelog remains the detailed source of truth.

## Headline

`2.1.0` is the first larger Factorio `2.1` feature wave after the `2.0.5` quick patch. It focuses on better settings control, safer icon selection, fluid-output productivity, and an opt-in pipeline extent setting.

## What Changed

- Added settings modes: Custom/manual, Vanilla-respectful, Megabase-balanced, and Unlimited sandbox.
- Added per-technology enable policies so generated research can use the selected settings mode, be force-enabled, or be force-disabled.
- Scripted Spoilage Preservation and Agricultural Growth Speed now follow the same effective enablement rules as data-stage generated technologies.
- Added better icon source resolution. MIR can prefer loaded Space Age art, use base-game fallbacks, or opt into installed-but-disabled Space Age icon files when the user explicitly enables that option.
- Added fluid-output productivity research for oil processing, oil cracking, lubricant, sulfuric acid, thruster fuel, and thruster oxidizer recipes where those recipes exist.
- Added an opt-in startup-only pipeline extent multiplier. The default `1x` setting leaves prototypes unchanged.

## Compatibility And Validation

- Added fixture validation for settings presets, forced enable/disable overrides, scripted runtime routing, icon source selection, fluid-output recipe ownership, and pipeline extent scaling.
- Base-only validation confirms generated icons do not use Space Age asset paths unless the installed Space Age icon opt-in is enabled.
- Fluid productivity validation confirms the implemented fluid recipe streams have exact recipe ownership and avoid duplicate infinite owners.
- Pipeline validation confirms the default `1x` setting does not run the prototype pass, and that explicit non-default values mutate representative fluid boxes.

## Known Notes

- Recipe productivity still respects Factorio's normal productivity cap.
- Spoilage Preservation and Agricultural Growth Speed remain disabled by default and should be treated as experimental.
- Existing planted crops are not globally rescanned by Agricultural Growth Speed.
- The pipeline extent multiplier is a startup setting, not research. Non-default values should be tested carefully in large or heavily modded fluid networks.
- Native modifier overlap policy, existing agricultural plant rescale, and high-throughput pump work remain deferred unless separately implemented and validated.

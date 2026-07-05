# More Infinite Research 1.9.5 Release Notes

This is the short, player-facing release summary for the `1.9.5` legacy mod portal release notes. It is derived from `changelog.txt`; the changelog remains the detailed source of truth.

## Headline

`1.9.5` is the Factorio `2.0` compatibility port of the tested More Infinite Research `2.1.0` source snapshot.

## What Changed

- Backported the `2.1.0` recipe-productivity ownership safeguards, vanilla productivity-family adoption, fluid-output productivity streams, icon resolver, docs structure, and validation tooling where they are compatible with Factorio `2.0`.
- Updated legacy metadata to `factorio_version = "2.0"` with `base >= 2.0`.
- Kept Quality as a hidden optional dependency and Space Age as an optional dependency without Factorio `2.1` dependency floors.
- Removed Factorio `2.1`-only cargo logistics technology modifiers from the legacy direct-effect set.

## Known Notes

- Recipe productivity still respects Factorio's normal productivity cap.
- Spoilage Preservation and Agricultural Growth Speed remain disabled by default and should be treated as experimental.
- Factorio `2.1` cargo landing pad count and cargo bay unloading distance research are not included in this legacy release.

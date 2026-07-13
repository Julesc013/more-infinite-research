# More Infinite Research 0.10.0

This branch is the finite museum edition for Factorio 0.10.12. It does not use later infinite-research fields or MIR's modern runtime compiler.

The mod adds configurable numbered continuations for inserter capacity, gun-turret damage, bullet shooting speed, bullet damage, and toolbelt rows. Every continuation uses the four target-era science packs and ends at a compiled hard limit.

Edit `config.lua` in an extracted mod directory to disable a family or lower its number of emitted levels. Factorio 0.10.12 loads the release ZIP directly.

Build the deterministic release archive with `./scripts/Build-MIRPackage.ps1`. The archive contains only `info.json`, `config.lua`, `data.lua`, and the English locale file. Visual technology-tree, icon, locale-fit, and balance review remains a maintainer gate.

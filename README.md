# More Infinite Research 0.12.0

This branch is the finite museum edition for Factorio 0.12.35. It does not use Factorio's later infinite-research fields or MIR's modern runtime compiler.

The mod adds configurable numbered continuations for inserter capacity, gun-turret damage, bullet shooting speed, bullet damage, toolbelt rows, and character logistic trash slots. Every continuation uses the four science packs shipped by Factorio 0.12.35 and ends at a compiled hard limit.

Edit `config.lua` in an extracted mod directory to disable a family or lower its number of emitted levels. The release ZIP uses the documented defaults and is loadable directly by Factorio 0.12.35.

Build the deterministic release archive with:

```powershell
.\scripts\Build-MIRPackage.ps1
```

The release archive contains only `info.json`, `config.lua`, `data.lua`, and the English locale file. Visual technology-tree, icon, locale-fit, and balance review remains a maintainer gate.

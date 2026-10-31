# Public API namespace collision

Use this fixture with `../api-namespace-beta` and `../../profiles/api-namespace-collision-f210-2123.json` on exact Factorio 2.1.23. Both consumers own an incompatible private `platform.target` module. Alpha publishes gear productivity during `data.lua`; beta publishes cable productivity during `data-final-fixes.lua`. They require MIR's public version and capabilities, distinct immediate native effects and unchanged private module identity.

The runtime observers read each actual native technology prototype and emit separate `MIR5_API_NAMESPACE_ALPHA` and `MIR5_API_NAMESPACE_BETA` markers. They earn no research, change no aggregate bonuses and repair no state. This case qualifies cross-mod loading and publication; the other API laboratory, runtime-query, optional-absence and multiplayer cases retain their separate acceptance requirements.

The host control executes both fixture data/control files and opposing wrong-target/effect cases. Loading the former unqualified MIR import against either consumer fails before publication. A host pass is not a native result. The two consumer roots each have exactly four packaged members: `info.json`, their data-stage entry point, `control.lua` and `platform/target.lua`; this README stays outside the test ZIP.

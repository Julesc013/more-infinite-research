# All-five native-credit upstream scaffold

This controlled upstream fixture supplies the named Space Age recipe and public-reference shapes only when an exact engine's raw data does not already provide them. It contains no MIR code, control stage or saved-state logic.

It lets the all-five vector fixture run a real MIR data/final-fixes composition in the small Lua host environment, whose reduced raw oracle deliberately omits the stock Space Age rows. On an engine that already supplies the named stock rows, it emits nothing for those identities. It is a synthetic test mechanism, not a claim about a reporter's modpack or a substitute for the engine's own prototype data.

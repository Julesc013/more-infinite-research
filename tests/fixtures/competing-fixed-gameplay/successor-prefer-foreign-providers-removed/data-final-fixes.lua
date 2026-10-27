-- Provider removal must preserve MIR's own remaining rows without importing a
-- foreign definition.  Preflight the exact fully covered MIR bioflux row before
-- reducing this disposable fixture's single real lab completion.
local bioflux = require("full-bioflux-data")
assert(mods.base == "2.0.77" and mods["space-age"] == "2.0.77"
  and mods["more-infinite-research"] == "5.0.20000"
  and mods["plates-n-circuit-productivity"] == nil
  and mods.Science_packs_productivity == nil
  and mods["bioflux-productivity"] == nil
  and mods["fish-productivity"] == nil, "unexpected fixed-provider removal closure")
local full = bioflux.assert_row(assert(data.raw.technology[bioflux.name],
  "MIR bioflux row is absent after fixed-provider removal"), nil,
  "captured provider-absent MIR bioflux")
bioflux.accelerate(full)

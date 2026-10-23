-- This shared module is safe while control.lua is loading and while on_load
-- runs: package composition injects one immutable target-literal.lua for the
-- exact engine selected by the historical fixture profile.
return require("target-literal")

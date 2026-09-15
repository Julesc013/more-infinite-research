-- Factorio 1 targets deliberately do not own scripted research effects.
-- Keep the package import explicit and fail closed if a caller bypasses the
-- target feature gate in prototypes/mir/stage/control.lua.

local M = {}
M.requires_features = {"scripted_techs"}

function M.register()
  error("MIR scripted research effects are disabled by the active Factorio-1 target profile.", 2)
end

return M

-- Disposable F200 settings for the current-MIR foreign-cap baseline route.
-- The ordinary gear effect remains one percent; stages differ only by cap.
local M = {}

local CAPS = {source = 0, finite = 1, relaxed = 0}

function M.apply(stage)
  local cap = CAPS[stage]
  if cap == nil then error("[mir5-f200-foreign-cap-baseline] unknown settings stage: " .. tostring(stage)) end
  local rows = data.raw
  local effect = rows["double-setting"] and rows["double-setting"]["ips-effect-per-level-research_gears"]
  local maximum = rows["int-setting"] and rows["int-setting"]["ips-max-level-research_gears"]
  if type(effect) ~= "table" or type(maximum) ~= "table" then
    error("[mir5-f200-foreign-cap-baseline] required gear settings are absent")
  end
  if maximum.minimum_value ~= nil and maximum.minimum_value > cap then
    error("[mir5-f200-foreign-cap-baseline] gear cap rejects stage value")
  end
  effect.default_value = 1
  maximum.default_value = cap
end

return M

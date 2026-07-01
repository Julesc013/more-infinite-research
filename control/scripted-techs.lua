local spoilage = require("control.effects.spoilage-preservation")
local agricultural_growth = require("control.effects.agricultural-growth-speed")

local M = {}

local features = {
  spoilage,
  agricultural_growth
}

local function ensure_storage()
  storage.mir = storage.mir or {}
  storage.mir.scripted_techs = storage.mir.scripted_techs or {}
  return storage.mir.scripted_techs
end

local function debug_enabled()
  local setting = settings.startup["mir-debug-scripted-effects"]
  return setting and setting.value == true
end

local function log_debug(message)
  if debug_enabled() then
    log("[more-infinite-research] " .. message)
  end
end

local function run_all(method, event)
  ensure_storage()
  for _, feature in ipairs(features) do
    local handler = feature[method]
    if handler then
      handler(event, log_debug)
    end
  end
end

local function run_matching_research(method, event)
  if not (event and event.research and event.research.valid) then return end
  ensure_storage()
  for _, feature in ipairs(features) do
    if feature.technology_name == event.research.name then
      local handler = feature[method]
      if handler then handler(event, log_debug) end
    end
  end
end

local function register_event(event_id, handler)
  if event_id then
    script.on_event(event_id, handler)
  end
end

function M.register()
  script.on_init(function(event)
    run_all("on_init", event)
  end)

  script.on_configuration_changed(function(event)
    run_all("on_configuration_changed", event)
  end)

  register_event(defines.events.on_research_finished, function(event)
    run_matching_research("on_research_finished", event)
  end)

  register_event(defines.events.on_research_reversed, function(event)
    run_matching_research("on_research_reversed", event)
  end)

  register_event(defines.events.on_technology_effects_reset, function(event)
    run_all("on_technology_effects_reset", event)
  end)

  register_event(defines.events.on_tower_planted_seed, function(event)
    agricultural_growth.on_tower_planted_seed(event, log_debug)
  end)
end

return M

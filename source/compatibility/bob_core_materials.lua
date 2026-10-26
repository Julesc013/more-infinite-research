-- Exact F210 no-Angel Bob Core material constructor.  It validates the seven
-- named routes and declared prerequisite references before returning fourteen
-- detached MIR technologies.  It does not search recipe, owner, or science
-- graphs.
local stages = require("research.material_stages")
local DEFINITIONS = require("research.bob_core_materials")
local routes = require("compatibility.material_routes")

local M = {}

local function fail(message)
  error("MIR5 F210 Bob Core material catalogue: " .. message, 3)
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function M.applies(active_mods)
  return require("compatibility.bob_core_profile").applies(active_mods)
end

local function stream_for(values, definition)
  local stream = type(values) == "table" and type(values.streams) == "table"
      and values.streams[definition.key] or nil
  if type(stream) ~= "table" or type(stream.enabled) ~= "boolean"
      or not finite(stream.base_cost) or stream.base_cost < 1
      or not finite(stream.linear_increment) or stream.linear_increment < 0
      or not finite(stream.growth_factor) or stream.growth_factor < 1
      or not finite(stream.max_level) or stream.max_level < 0 or stream.max_level ~= math.floor(stream.max_level)
      or not finite(stream.research_time) or stream.research_time <= 0
      or not finite(stream.effect_percent) or stream.effect_percent <= 0 then
    fail(definition.key .. " resolved settings are invalid")
  end
  return stream
end

local function continuation_description(definition, stream)
  -- The captured default tail displayed 150. At the default 2 percent and
  -- the declared threefold productivity ceiling, that is also the useful
  -- level bound selected by runtime.lifecycle when max_level is 0. The
  -- runtime later reads the effective named RecipePrototype cap after any
  -- prototype policy, so this data-stage caption is not a second cap policy.
  local useful = math.ceil(definition.productivity_ceiling * 100 / stream.effect_percent)
  local limit = stream.max_level > 0 and math.min(stream.max_level, useful) or useful
  return {"", {"technology-description.more-infinite-research.recipe_productivity"}, "\n",
    {"mod-setting-name.ips-max-level-stream", {"", {"description.productivity-bonus"}, ": ",
      {"item-name." .. definition.item}}}, ": ", tostring(limit)}
end


function M.technologies(values, raw, active_mods)
  if not M.applies(active_mods) then return {} end
  local streams = {}
  for index, definition in ipairs(DEFINITIONS) do
    routes.preflight(raw, definition, fail)
    streams[index] = stream_for(values, definition)
  end
  local output = {}
  for index, definition in ipairs(DEFINITIONS) do
    local stream = streams[index]
    output[#output + 1] = stages.technology(definition, definition.early, stream, fail)
    local continuation = stages.technology(definition, definition.continuation, stream, fail)
    continuation.localised_description = continuation_description(definition, stream)
    output[#output + 1] = continuation
  end
  return output
end

return M

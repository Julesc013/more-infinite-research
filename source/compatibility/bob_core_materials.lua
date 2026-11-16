-- Exact F210 no-Angel Bob Core material constructor.  It validates the seven
-- named routes and declared prerequisite references before returning fourteen
-- detached MIR technologies. The process-return check shares one ingredient
-- index; it does not discover owners or science progression.
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

function M.technologies(values, raw, active_mods, return_context)
  if not M.applies(active_mods) then return {} end
  local streams = {}
  for index, definition in ipairs(DEFINITIONS) do
    routes.preflight(raw, definition, fail)
    streams[index] = stream_for(values, definition)
  end
  local returns = require("compatibility.material_returns")
  local context = return_context and return_context() or returns.prepare(raw)
  local unavailable = {}
  for _, definition in ipairs(DEFINITIONS) do
    unavailable[definition.key] = routes.return_reason(raw, definition, context, fail) ~= nil
  end
  local output = {}
  for index, definition in ipairs(DEFINITIONS) do
    local stream = streams[index]
    local early = stages.technology(definition, definition.early, stream, fail)
    local continuation = stages.technology(definition, definition.continuation, stream, fail)
    -- The shared caption reports the useful ceiling (150 at the captured
    -- default) when max_level is zero. Runtime still reads the effective
    -- named RecipePrototype cap after policy, so this is not a second cap
    -- policy.
    continuation.localised_description = stages.continuation_description(definition, stream)
    if unavailable[definition.key] then
      stages.retain_disabled(early)
      stages.retain_disabled(continuation)
    end
    output[#output + 1] = early
    output[#output + 1] = continuation
  end
  return output
end

return M

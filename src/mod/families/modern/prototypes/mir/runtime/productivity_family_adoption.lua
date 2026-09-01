local M = {}
M.requires_features = {"productivity_family_adoption"}
local runtime_state = require("prototypes.mir.runtime.state")
local transition_descriptor = require("prototypes.mir.domain.research_cost.transition_descriptor")

local ADOPTION_DATA_NAME = "more-infinite-research-productivity-family-adoption"

local function ensure_state()
  return runtime_state.bucket("productivity_family_adoption")
end

local function adoption_data()
  local mod_data = prototypes and prototypes.mod_data and prototypes.mod_data[ADOPTION_DATA_NAME]
  return mod_data and mod_data.data or nil
end

local function current_adoption_state()
  local data = adoption_data()
  if not data then
    return {
      version = 0,
      count = 0,
      bindings = {},
      signature = ""
    }
  end

  local bindings = {}
  for _, binding in ipairs(data.bindings or {}) do
    local prototype = prototypes and prototypes.technology and prototypes.technology[binding.owner]
    bindings[tostring(binding.owner)] = {
      input_descriptor = binding.input_descriptor,
      output_descriptor = binding.output_descriptor,
      operation = binding.operation,
      configured_fields = binding.configured_fields,
      planned_max_level = binding.planned_max_level,
      observed_max_level = prototype and prototype.max_level or nil
    }
  end
  return {
    version = tonumber(data.version) or 0,
    count = tonumber(data.adopted_count) or 0,
    bindings = bindings,
    signature = tostring(data.signature or "")
  }
end

local function retain_engine_normalized_current_research_progress(previous_bindings, current_bindings)
  for _, force in pairs(game.forces) do
    local technology = force.current_research
    local current = technology and current_bindings[technology.name]
    if current then
      local previous = previous_bindings[technology.name] or {}
      local progress = force.research_progress
      local previous_cost, previous_error = transition_descriptor.evaluate(previous.output_descriptor, technology.level)
      local current_cost, current_error = transition_descriptor.evaluate(current.output_descriptor, technology.level)
      if previous_cost and current_cost and previous_cost ~= current_cost then
        log("[more-infinite-research] Retained Factorio-normalized current research progress for native owner "
          .. technology.name .. " at " .. tostring(progress)
          .. " after realized cost " .. tostring(previous_cost)
          .. " -> " .. tostring(current_cost) .. "; no second conversion was applied.")
      elseif previous.output_descriptor and (not previous_cost or not current_cost) then
        log("[more-infinite-research] Left Factorio-normalized current research progress unchanged for native owner "
          .. technology.name .. " because descriptor evaluation was unavailable: "
          .. tostring(previous_error or current_error) .. ".")
      elseif not previous.output_descriptor then
        log("[more-infinite-research] Retained Factorio-normalized current research progress for native owner "
          .. technology.name .. " at " .. tostring(progress)
          .. "; the prior adoption schema has no exact output descriptor, so no second conversion was applied.")
      end
    end
  end
end

function M.on_init()
  local current = current_adoption_state()
  local state = ensure_state()
  state.version = current.version
  state.adopted_count = current.count
  state.bindings = current.bindings
  state.signature = current.signature
end

function M.on_configuration_changed()
  local current = current_adoption_state()
  local state = ensure_state()
  local previous_bindings = state.bindings or {}
  local previous_signature = state.signature

  if previous_signature == nil and current.signature == "" then
    state.version = current.version
    state.adopted_count = current.count
    state.bindings = current.bindings
    state.signature = current.signature
    return
  end

  if previous_signature == current.signature then
    state.version = current.version
    state.adopted_count = current.count
    state.bindings = current.bindings
    return
  end

  retain_engine_normalized_current_research_progress(previous_bindings, current.bindings)
  state.version = current.version
  state.adopted_count = current.count
  state.bindings = current.bindings
  state.signature = current.signature
  log("[more-infinite-research] Preserved technology effects without a force-wide reset for productivity family adoption signature change"
    .. " (adopted recipes: "
    .. tostring(current.count)
    .. ", signature: "
    .. tostring(current.signature)
    .. ").")
end

return M

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
    bindings[tostring(binding.owner)] = {
      input_descriptor = binding.input_descriptor,
      output_descriptor = binding.output_descriptor
    }
  end
  return {
    version = tonumber(data.version) or 0,
    count = tonumber(data.adopted_count) or 0,
    bindings = bindings,
    signature = tostring(data.signature or "")
  }
end

local function restore_current_research_progress(previous_bindings, current_bindings)
  for _, force in pairs(game.forces) do
    local technology = force.current_research
    local current = technology and current_bindings[technology.name]
    if current then
      local previous = previous_bindings[technology.name] or {}
      -- A stored v2 binding has no descriptor. On the first v3 transition,
      -- the current input descriptor is the exact pre-change model.
      local previous_descriptor = previous.output_descriptor or current.input_descriptor
      local before = force.research_progress
      local restored, detail = transition_descriptor.convert_fraction(
        before, previous_descriptor, current.output_descriptor, technology.level)
      if restored and detail.previous_cost ~= detail.current_cost then
        force.research_progress = restored
        log("[more-infinite-research] Preserved current research progress for native owner "
          .. technology.name .. " from " .. tostring(before) .. " to " .. tostring(restored)
          .. " using realized cost " .. tostring(detail.previous_cost)
          .. " -> " .. tostring(detail.current_cost) .. ".")
      elseif not restored then
        log("[more-infinite-research] Refused unsafe current research progress conversion for native owner "
          .. technology.name .. ": " .. tostring(detail) .. ".")
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

  restore_current_research_progress(previous_bindings, current.bindings)
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

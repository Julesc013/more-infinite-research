local M = {}
M.requires_features = {"productivity_family_adoption"}
local runtime_state = require("prototypes.mir.runtime.state")

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
      signature = ""
    }
  end

  return {
    version = tonumber(data.version) or 0,
    count = tonumber(data.adopted_count) or 0,
    signature = tostring(data.signature or "")
  }
end

function M.on_init()
  local current = current_adoption_state()
  local state = ensure_state()
  state.version = current.version
  state.adopted_count = current.count
  state.signature = current.signature
end

function M.on_configuration_changed()
  local current = current_adoption_state()
  local state = ensure_state()
  local previous_signature = state.signature

  if previous_signature == nil and current.signature == "" then
    state.version = current.version
    state.adopted_count = current.count
    state.signature = current.signature
    return
  end

  if previous_signature == current.signature then
    state.version = current.version
    state.adopted_count = current.count
    return
  end

  for _, force in pairs(game.forces) do
    force.reset_technology_effects()
  end
  state.version = current.version
  state.adopted_count = current.count
  state.signature = current.signature
  log("[more-infinite-research] Reset technology effects for productivity family adoption signature change"
    .. " (adopted recipes: "
    .. tostring(current.count)
    .. ", signature: "
    .. tostring(current.signature)
    .. ").")
end

return M

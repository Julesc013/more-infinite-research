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
      bindings = {},
      signature = ""
    }
  end

  local bindings = {}
  for _, binding in ipairs(data.bindings or {}) do
    bindings[tostring(binding.owner)] = {
      input_unit = binding.input_unit or {},
      output_unit = binding.output_unit or {}
    }
  end
  return {
    version = tonumber(data.version) or 0,
    count = tonumber(data.adopted_count) or 0,
    bindings = bindings,
    signature = tostring(data.signature or "")
  }
end

local function compact(value)
  return tostring(value or ""):gsub("%s+", "")
end

local function research_unit_count(unit, level)
  if type(unit) ~= "table" then return nil end
  if type(unit.count) == "number" then return math.floor(unit.count) end
  local formula = compact(unit.count_formula)
  local growth, base = formula:match("^([%d%.]+)%^L%*([%d%.]+)$")
  if growth and base then return math.floor(tonumber(growth) ^ level * tonumber(base)) end
  base, growth = formula:match("^([%d%.]+)%*([%d%.]+)%^%(L%-1%)$")
  if base and growth then return math.floor(tonumber(base) * tonumber(growth) ^ (level - 1)) end
  return nil
end

local function restore_current_research_progress(previous_bindings, current_bindings)
  for _, force in pairs(game.forces) do
    local technology = force.current_research
    local current = technology and current_bindings[technology.name]
    if current then
      local previous = previous_bindings[technology.name] or {output_unit = current.input_unit}
      local previous_count = research_unit_count(previous.output_unit, technology.level)
      local current_count = research_unit_count(current.output_unit, technology.level)
      if previous_count and current_count and previous_count > 0 and current_count > 0
          and previous_count ~= current_count then
        local before = force.research_progress
        local restored = math.max(0, math.min(1, before * current_count / previous_count))
        force.research_progress = restored
        log("[more-infinite-research] Preserved current research progress for native owner "
          .. technology.name .. " from " .. tostring(before) .. " to " .. tostring(restored) .. ".")
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

local M = {}
M.requires_features = {"scripted_techs"}

local runtime_state = require("prototypes.mir.runtime.state")

local POLICY_DATA_NAME = "more-infinite-research-maximum-level-policy"
local POLICY_VERSION = 1
local INFINITE_RUNTIME_MAX_LEVEL = 4294967295

local function ensure_state()
  return runtime_state.bucket("maximum_level_control")
end

local function observed_max_level(name)
  local prototype = prototypes and prototypes.technology and prototypes.technology[name]
  return prototype and prototype.max_level or nil
end

local function prototype_is_infinite(value)
  return value == "infinite"
    or (type(value) == "number" and value >= INFINITE_RUNTIME_MAX_LEVEL)
end

local function current_policy()
  local managed = {}
  local caps = {}
  local policy_prototype = prototypes and prototypes.mod_data
    and prototypes.mod_data[POLICY_DATA_NAME]
  local policy_data = policy_prototype and policy_prototype.data or nil
  for _, binding in ipairs((policy_data and policy_data.bindings) or {}) do
    local name = tostring(binding.technology)
    managed[name] = {
      source = binding.source,
      operation = binding.operation,
      setting = binding.setting,
      selected = binding.selected
    }
  end

  for name, policy in pairs(managed) do
    local selected = policy.selected
    if type(selected) == "number" and selected > 0 then
      local observed = observed_max_level(name)
      if prototype_is_infinite(observed) then
        caps[name] = math.floor(selected)
      else
        log("[more-infinite-research] Maximum-level conflict technology=" .. name
          .. " selected=" .. tostring(selected)
          .. " planned=" .. tostring(selected)
          .. " final-observed=" .. tostring(observed)
          .. " binding-operation=" .. tostring(policy.operation)
          .. " source=" .. tostring(policy.source)
          .. " reason=late_prototype_mutation"
          .. " setting=" .. tostring(policy.setting)
          .. "; lossless runtime cap enforcement was refused.")
      end
    end
  end
  return managed, caps
end

local function force_cap_state(force)
  local state = ensure_state()
  state.disabled_by_cap = state.disabled_by_cap or {}
  state.disabled_by_cap[force.index] = state.disabled_by_cap[force.index] or {}
  return state.disabled_by_cap[force.index]
end

local function normalize_force(force, managed, caps)
  local disabled_by_cap = force_cap_state(force)
  local next_level = {}
  for technology_name, cap in pairs(caps) do
    local technology = force.technologies[technology_name]
    if technology then next_level[technology_name] = technology.level end
  end

  local prior_current = force.current_research
  local prior_current_name = prior_current and prior_current.name or nil
  local prior_progress = prior_current and force.research_progress or nil
  local filtered = {}
  local removed = {}
  for _, technology in ipairs(force.research_queue or {}) do
    local cap = caps[technology.name]
    local level = next_level[technology.name]
    if not cap or not level or level <= cap then
      table.insert(filtered, technology)
      if level then next_level[technology.name] = level + 1 end
    else
      table.insert(removed, technology.name .. "@" .. tostring(level))
    end
  end

  if #removed > 0 then
    force.research_queue = filtered
    local current = force.current_research
    if prior_current_name and current and current.name == prior_current_name and prior_progress then
      force.research_progress = prior_progress
    end
    log("[more-infinite-research] Normalized research above configured maximum"
      .. " force=" .. tostring(force.name)
      .. " removed=" .. table.concat(removed, ",")
      .. " retained-current=" .. tostring(current and current.name or "none")
      .. " completed-levels=retained.")
  end

  local all_managed = {}
  for technology_name, _ in pairs(managed) do all_managed[technology_name] = true end
  for technology_name, _ in pairs(ensure_state().managed_technologies or {}) do
    all_managed[technology_name] = true
  end
  for technology_name, _ in pairs(all_managed) do
    local technology = force.technologies[technology_name]
    local cap = caps[technology_name]
    local should_disable = technology and cap and technology.level > cap
    if should_disable then
      if technology.enabled then
        technology.enabled = false
        disabled_by_cap[technology_name] = true
      end
    elseif technology and disabled_by_cap[technology_name] then
      technology.enabled = true
      disabled_by_cap[technology_name] = nil
    end
  end
end

local function normalize_all()
  local managed, caps = current_policy()
  for _, force in pairs(game.forces) do normalize_force(force, managed, caps) end
  local state = ensure_state()
  state.managed_technologies = managed
  state.policy_version = POLICY_VERSION
end

function M.on_init()
  normalize_all()
end

function M.on_configuration_changed()
  normalize_all()
end

function M.on_research_finished() normalize_all() end
function M.on_research_reversed() normalize_all() end
function M.on_research_queued() normalize_all() end
function M.on_technology_effects_reset() normalize_all() end
function M.on_force_created() normalize_all() end
function M.on_forces_merged() normalize_all() end

return M

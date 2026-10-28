-- One-time preservation of MIR 1.2's earned combined rocket/cannon stream.
--
-- The published 1.2.0, 1.2.5, and 1.2.9 archives each emitted rocket and
-- cannon-shell gun-speed effects from the same public rocket identity.  MIR5
-- retains rocket publicly and deliberately gives cannon its own public row.
-- This holder restores only completed old combined levels, with no ledger,
-- recipe scan, research callback, tick work, or public-row mutation.
local definitions = require("research.legacy_cannon_credit_definitions")
local platform_target = require("platform.target")

local M = {}

local UINT32_MAX = 4294967295
local MIR_MOD = "more-infinite-research"
local PUBLISHED_COMBINED_VERSIONS = {
  ["1.2.0"] = true,
  ["1.2.5"] = true,
  ["1.2.9"] = true,
}
local DESCRIPTOR = definitions.descriptor()

local function finite_nonnegative(value)
  return type(value) == "number" and value == value and value >= 0
    and value < math.huge
end

local function integer(value)
  return type(value) == "number" and value == value and value ~= math.huge
    and value ~= -math.huge and value == math.floor(value)
end

local function valid_force(force)
  return force and force.valid ~= false and integer(force.index) and force.index > 0
end

local function active_target()
  local active = script and script.active_mods
  if type(active) ~= "table" or active["space-age"] ~= nil then return nil end
  if platform_target.recipe_productivity ~= true
      or (platform_target.id ~= "f200" and platform_target.id ~= "f210")
      or type(platform_target.distribution_version) ~= "string"
      or active[MIR_MOD] ~= platform_target.distribution_version then
    return nil
  end
  return platform_target.id
end

local function target_for_event(event)
  if type(event) ~= "table" then return nil end
  local changes = event.mod_changes
  local change = type(changes) == "table" and changes[MIR_MOD] or nil
  if type(change) ~= "table" or PUBLISHED_COMBINED_VERSIONS[change.old_version] ~= true then return nil end
  local target = active_target()
  if target == nil then return nil end
  if change.new_version ~= platform_target.distribution_version then
    error("MIR legacy cannon credit does not admit this destination version", 3)
  end
  return target
end

local function completed(technology)
  if technology == nil or technology.valid == false or not integer(technology.level)
      or technology.level < 1 or technology.level > UINT32_MAX
      or type(technology.researched) ~= "boolean" then
    return nil
  end
  return technology.level - 1 + (technology.researched and 1 or 0)
end

local function public_rocket(technology)
  local prototype = technology and technology.prototype
  local effects = prototype and prototype.effects
  if technology == nil or technology.valid == false or technology.name ~= DESCRIPTOR.main_id
      or prototype == nil or prototype.name ~= DESCRIPTOR.main_id or prototype.level ~= 1
      or prototype.max_level ~= UINT32_MAX or prototype.hidden == true or prototype.upgrade ~= true
      or type(prototype.enabled) ~= "boolean" or type(technology.enabled) ~= "boolean"
      or type(effects) ~= "table" or #effects ~= 1 then
    return nil
  end
  local effect = effects[1]
  if type(effect) ~= "table" or effect.type ~= "gun-speed"
      or effect.ammo_category ~= DESCRIPTOR.source_category or not finite_nonnegative(effect.modifier) then
    return nil
  end
  local count = completed(technology)
  if count == nil then return nil end
  return count, effect.modifier
end

local function one_automation_pack(ingredients)
  if type(ingredients) ~= "table" or #ingredients ~= 1 then return false end
  local item = ingredients[1]
  return type(item) == "table" and item.name == "automation-science-pack" and item.amount == 1
end

local function exact_holder_shape(technology, scalar)
  local prototype = technology and technology.prototype
  local effects = prototype and prototype.effects
  if technology == nil or technology.valid == false or technology.name ~= DESCRIPTOR.id
      or prototype == nil or prototype.name ~= DESCRIPTOR.id or prototype.level ~= 1
      or prototype.max_level ~= UINT32_MAX or prototype.hidden ~= true or prototype.upgrade ~= true
      or prototype.enabled ~= false or prototype.visible_when_disabled ~= false
      or type(effects) ~= "table" or #effects ~= 1
      -- The authored unit.time is one second; LuaTechnology exposes 60 ticks.
      or technology.research_unit_count ~= 1 or technology.research_unit_energy ~= 60
      or not one_automation_pack(technology.research_unit_ingredients)
      or type(technology.enabled) ~= "boolean" or type(technology.visible_when_disabled) ~= "boolean" then
    return false
  end
  local effect = effects[1]
  if type(effect) ~= "table" or effect.type ~= "gun-speed"
      or effect.ammo_category ~= DESCRIPTOR.credit_category
      -- Both fields originate from the same selected data-stage scalar. Exact
      -- equality accepts a target's native float representation without a
      -- broad numeric tolerance or a default-percent substitution.
      or effect.modifier ~= scalar then
    return false
  end
  return completed(technology) ~= nil
end

local function force_plan(force)
  if not valid_force(force) or force.technologies == nil then return nil end
  local completed_levels, scalar = public_rocket(force.technologies[DESCRIPTOR.main_id])
  if completed_levels == nil then return nil end
  local holder = force.technologies[DESCRIPTOR.id]
  if not exact_holder_shape(holder, scalar) or holder.enabled ~= false
      or holder.visible_when_disabled ~= false or holder.researched ~= false then
    return nil
  end
  if completed_levels == 0 then
    if holder.level == 1 then return false end
    return nil
  end
  local wanted = 1 + completed_levels
  if wanted > UINT32_MAX then return nil end
  if holder.level == 1 then return {index = force.index, completed = completed_levels, level = wanted} end
  if holder.level == wanted then return false end
  return nil
end

local function valid_plan(plan)
  if type(plan) ~= "table" or (plan.target ~= "f200" and plan.target ~= "f210")
      or type(plan.forces) ~= "table" then return false end
  local seen = {}
  for index = 1, #plan.forces do
    local row = plan.forces[index]
    if type(row) ~= "table" or not integer(row.index) or row.index <= 0 or seen[row.index]
        or not integer(row.completed) or row.completed <= 0
        or not integer(row.level) or row.level ~= row.completed + 1 or row.level > UINT32_MAX then
      return false
    end
    seen[row.index] = true
  end
  return true
end

-- This pass reads every relevant named public/holder pair before any holder
-- write.  The detached plan has only indexes and completed-level counts.
function M.preflight(event)
  local target = target_for_event(event)
  if target == nil then return nil end
  if not game or not game.forces then error("MIR legacy cannon credit requires the force collection", 2) end
  local plan = {target = target, forces = {}}
  for _, force in pairs(game.forces) do
    if valid_force(force) then
      local row = force_plan(force)
      if row == nil then error("MIR legacy cannon credit rejects a non-current force shape", 2) end
      if row ~= false then plan.forces[#plan.forces + 1] = row end
    end
  end
  table.sort(plan.forces, function(left, right) return left.index < right.index end)
  if #plan.forces == 0 then return nil end
  return plan
end

function M.apply(plan)
  if plan == nil then return false end
  if not valid_plan(plan) then error("MIR invalid legacy cannon credit plan", 2) end
  if active_target() ~= plan.target then error("MIR legacy cannon credit plan target is no longer active", 2) end
  if not game or not game.forces then error("MIR legacy cannon credit requires the force collection", 2) end

  local forces_by_index = {}
  for _, force in pairs(game.forces) do
    if valid_force(force) then
      if forces_by_index[force.index] ~= nil then error("MIR legacy cannon credit rejects duplicate force indexes", 2) end
      forces_by_index[force.index] = force
    end
  end
  local live = {}
  for index = 1, #plan.forces do
    local row = plan.forces[index]
    local force = forces_by_index[row.index]
    local current = force and force_plan(force) or nil
    if current == nil or current == false or current.completed ~= row.completed or current.level ~= row.level then
      error("MIR legacy cannon credit plan no longer matches a current force", 2)
    end
    live[index] = force
  end
  for index = 1, #live do
    local holder = live[index].technologies[DESCRIPTOR.id]
    holder.level = plan.forces[index].level
    -- Native level assignment can re-enable hidden technology.  Restore only
    -- this holder's flags after our exact named write.
    holder.enabled = false
    holder.visible_when_disabled = false
  end
  return true
end

function M.on_configuration_changed(event)
  return M.apply(M.preflight(event))
end

-- Configuration/DLC effect rebuilds can re-enable a hidden carrier.  This
-- cleanup never changes its level, public row, force aggregate, queue, or
-- saved state, and is deliberately limited to the one authored identity.
function M.on_technology_effects_reset(event)
  local force = event and event.force
  if not valid_force(force) or force.technologies == nil then return false end
  local _, scalar = public_rocket(force.technologies[DESCRIPTOR.main_id])
  local holder = force.technologies[DESCRIPTOR.id]
  if scalar == nil or not exact_holder_shape(holder, scalar) then return false end
  holder.enabled = false
  holder.visible_when_disabled = false
  return true
end

return M

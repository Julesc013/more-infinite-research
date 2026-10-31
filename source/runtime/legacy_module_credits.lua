-- One-time preservation of MIR 1.1's earned tier-one module .01 effects.
--
-- This is intentionally narrower than native_credits: it recognizes exactly
-- the published 1.1.0 -> MIR5 F200/F210 Base configuration event, reads only
-- the named public module row and three authored hidden holders. Native holder
-- levels retain the actual credit; no
-- recipe scan, research subscription, tick work, or historical ledger exists.
local definitions = require("research.legacy_module_credit_definitions")
local platform_target = require("platform.target")

local M = {}

local SCHEMA = 1
local UINT32_MAX = 4294967295
local EFFECT_TOLERANCE = .00000001
local MIR_MOD = "more-infinite-research"
local PUBLISHED_VERSION = "1.1.0"
local MAIN_ID = "recipe-prod-research_modules-1"
local DESCRIPTORS = definitions.descriptors()
local MAIN_EFFECTS = {
  ["efficiency-module"] = .1,
  ["productivity-module"] = .1,
  ["speed-module"] = .1,
  ["efficiency-module-2"] = .05,
  ["productivity-module-2"] = .05,
  ["speed-module-2"] = .05,
  ["efficiency-module-3"] = .02,
  ["productivity-module-3"] = .02,
  ["speed-module-3"] = .02,
}

local function close(left, right)
  return type(left) == "number" and type(right) == "number"
    and left == left and right == right and math.abs(left - right) <= EFFECT_TOLERANCE
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
  if not active or active["space-age"] ~= nil then return nil end
  if platform_target.recipe_productivity ~= true
      or (platform_target.id ~= "f200" and platform_target.id ~= "f210")
      or type(platform_target.distribution_version) ~= "string"
      or active[MIR_MOD] ~= platform_target.distribution_version then return nil end
  return platform_target.id
end

local function target_for_event(event)
  if type(event) ~= "table" then return nil end
  local changes = event.mod_changes
  local change = type(changes) == "table" and changes[MIR_MOD] or nil
  if type(change) ~= "table" or change.old_version ~= PUBLISHED_VERSION then return nil end
  local target = active_target()
  if target ~= nil and change.new_version == platform_target.distribution_version then return target end
  if target == nil then return nil end
  if change.new_version ~= platform_target.distribution_version then
    error("MIR legacy module credit does not admit this destination version", 3)
  end
end

local function completed(technology)
  if technology == nil or technology.valid == false or not integer(technology.level)
      or technology.level < 1 or technology.level > UINT32_MAX
      or type(technology.researched) ~= "boolean" then
    return nil
  end
  return technology.level - 1 + (technology.researched and 1 or 0)
end

local function exact_main(technology)
  local prototype = technology and technology.prototype
  local effects = prototype and prototype.effects
  -- A cap or foreign owner may disable further research without removing
  -- already-earned effects. This bridge never writes public enablement.
  if technology == nil or technology.valid == false or technology.name ~= MAIN_ID
      or prototype == nil or prototype.name ~= MAIN_ID or prototype.level ~= 1
      or prototype.max_level ~= UINT32_MAX or prototype.hidden == true or prototype.upgrade ~= true
      or type(prototype.enabled) ~= "boolean" or type(technology.enabled) ~= "boolean"
      or type(effects) ~= "table" or #effects ~= 9 or completed(technology) == nil then
    return nil
  end
  local found = {}
  for index = 1, #effects do
    local effect = effects[index]
    if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity"
        or type(effect.recipe) ~= "string" or found[effect.recipe] ~= nil
        or not close(effect.change, MAIN_EFFECTS[effect.recipe]) then
      return nil
    end
    found[effect.recipe] = true
  end
  for recipe in pairs(MAIN_EFFECTS) do if found[recipe] ~= true then return nil end end
  return completed(technology)
end

local function one_automation_pack(ingredients)
  if type(ingredients) ~= "table" or #ingredients ~= 1 then return false end
  local item = ingredients[1]
  return type(item) == "table" and item.name == "automation-science-pack" and item.amount == 1
end

local function exact_holder_shape(technology, descriptor)
  local prototype = technology and technology.prototype
  local effects = prototype and prototype.effects
  if technology == nil or technology.valid == false or technology.name ~= descriptor.id
      or prototype == nil or prototype.name ~= descriptor.id or prototype.level ~= 1
      or prototype.max_level ~= UINT32_MAX or prototype.hidden ~= true
      or prototype.upgrade ~= true or prototype.enabled ~= false or prototype.visible_when_disabled ~= false
      or type(effects) ~= "table" or #effects ~= 1
      -- The authored definition uses unit.time = 1 second.  LuaTechnology
      -- exposes that duration as 60 ticks, not as the authored seconds.
      or technology.research_unit_count ~= 1 or not close(technology.research_unit_energy, 60)
      or not one_automation_pack(technology.research_unit_ingredients)
      or type(technology.enabled) ~= "boolean" or type(technology.visible_when_disabled) ~= "boolean" then
    return false
  end
  local effect = effects[1]
  if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity"
      or effect.recipe ~= descriptor.recipe or not close(effect.change, descriptor.change) then
    return false
  end
  return completed(technology) ~= nil
end

local function holder_mode(technology, descriptor, completed_levels)
  if not exact_holder_shape(technology, descriptor)
      or technology.enabled ~= false or technology.visible_when_disabled ~= false
      or technology.researched ~= false then
    return nil
  end
  if technology.level == 1 then return "initial" end
  if completed_levels > 0 and technology.level == 1 + completed_levels then return "credited" end
  return nil
end

local function detached_force_plan(force)
  if not valid_force(force) or force.technologies == nil then return nil end
  local completed_levels = exact_main(force.technologies[MAIN_ID])
  if completed_levels == nil then return nil end
  local mode = nil
  for index = 1, #DESCRIPTORS do
    local holder = holder_mode(force.technologies[DESCRIPTORS[index].id], DESCRIPTORS[index], completed_levels)
    if holder == nil or (mode ~= nil and mode ~= holder) then return nil end
    mode = holder
  end
  if completed_levels == 0 or mode == "credited" then return false end
  return {index = force.index, completed = completed_levels, holder_level = 1 + completed_levels}
end

local function valid_plan(plan)
  if type(plan) ~= "table" or plan.schema ~= SCHEMA or type(plan.target) ~= "string"
      or type(plan.forces) ~= "table" or (plan.target ~= "f200" and plan.target ~= "f210") then
    return false
  end
  local seen = {}
  for index = 1, #plan.forces do
    local row = plan.forces[index]
    if type(row) ~= "table" or not integer(row.index) or row.index <= 0
        or not integer(row.completed) or row.completed < 0
        or not integer(row.holder_level) or row.holder_level ~= row.completed + 1
        or row.holder_level > UINT32_MAX or seen[row.index] then
      return false
    end
    seen[row.index] = true
  end
  return true
end

-- Preflight contains no technology write. Its result carries only
-- force indexes and level counts, so callers cannot smuggle live objects from
-- an unvalidated force into the later apply phase.
function M.preflight(event)
  local target = target_for_event(event)
  if target == nil then return nil end
  if not game or not game.forces then
    error("MIR legacy module credit requires the force collection", 2)
  end
  local plan = {schema = SCHEMA, target = target, forces = {}}
  for _, force in pairs(game.forces) do
    if valid_force(force) then
      local row = detached_force_plan(force)
      if row == nil then error("MIR legacy module credit rejects a non-current force shape", 2) end
      if row ~= false then plan.forces[#plan.forces + 1] = row end
    end
  end
  table.sort(plan.forces, function(left, right) return left.index < right.index end)
  if #plan.forces == 0 then return nil end
  return plan
end

-- Apply repeats every shape check before the first holder write. This keeps a
-- plan safe across lifecycle reconciliation without turning it into a second
-- historical-state database.
function M.apply(plan)
  if plan == nil then return false end
  if not valid_plan(plan) then error("MIR invalid legacy module credit plan", 2) end
  if active_target() ~= plan.target then error("MIR legacy module credit plan target is no longer active", 2) end
  if not game or not game.forces then error("MIR legacy module credit requires the force collection", 2) end
  local forces_by_index = {}
  for _, force in pairs(game.forces) do
    if valid_force(force) then
      if forces_by_index[force.index] ~= nil then
        error("MIR legacy module credit rejects duplicate force indexes", 2)
      end
      forces_by_index[force.index] = force
    end
  end
  local live = {}
  for index = 1, #plan.forces do
    local row = plan.forces[index]
    local force = forces_by_index[row.index]
    local current = force and detached_force_plan(force) or nil
    if current == nil or current == false or current.completed ~= row.completed
        or current.holder_level ~= row.holder_level then
      error("MIR legacy module credit plan no longer matches a current force", 2)
    end
    live[index] = force
  end
  for index = 1, #live do
    local force, row = live[index], plan.forces[index]
    for descriptor_index = 1, #DESCRIPTORS do
      local holder = force.technologies[DESCRIPTORS[descriptor_index].id]
      holder.level = row.holder_level
      holder.enabled = false
      holder.visible_when_disabled = false
    end
  end
  return true
end

function M.on_configuration_changed(event)
  return M.apply(M.preflight(event))
end

-- Effect reset can re-enable a holder after its level was written. Cleanup
-- touches only exact named holders; it never changes levels, public effects,
-- recipe bonuses, queues, or storage.
function M.on_technology_effects_reset(event)
  local force = event and event.force
  if not valid_force(force) or force.technologies == nil then return false end
  for index = 1, #DESCRIPTORS do
    local holder = force.technologies[DESCRIPTORS[index].id]
    if not exact_holder_shape(holder, DESCRIPTORS[index]) then return false end
  end
  for index = 1, #DESCRIPTORS do
    local holder = force.technologies[DESCRIPTORS[index].id]
    holder.enabled = false
    holder.visible_when_disabled = false
  end
  return true
end

return M

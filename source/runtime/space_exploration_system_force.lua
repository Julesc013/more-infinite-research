-- One profile bridge for SE's scripted NPC policy, never research
-- credit. SE 0.7.57 scripts/system-forces.lua owns these six defaults and
-- reapplies them on its reset events. No other force or upstream state is ours.
-- An intentional third-party all-zero override is indistinguishable from
-- the demonstrated loss. This restores SE's canonical policy, not arbitrary
-- former offsets, and does not fingerprint the rest of the modpack.
local M = {}
local target = require("platform.target")
local MIR = "more-infinite-research"
local RECOVERED_FORCE = "mir_se_conquest_policy_force"
local LOADERS = "aai-loaders"
local BASIC = {artillery=true, tank=true, radar=true, electronics=true,
  ["sulfur-processing"]=true, explosives=true, electricity=true,
  ["fuel-processing"]=true, ["repair-pack"]=true}
local DEFAULTS = {5.65, 3, 1.8, 6, 2.2, 5.1}
local TECHNOLOGY_LIMIT = 16384

local function require_policy(condition, reason)
  if not condition then error("MIR cannot restore Space Exploration conquest policy: " .. reason, 3) end
end

local function finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function historical_origin(changes, active)
  for name, change in pairs(changes) do
    if name ~= MIR then
      if type(change) ~= "table" or type(change.old_version) ~= "string"
          or type(change.new_version) ~= "string" or active[name] ~= change.new_version then return false end
      if (name == "base" or name == "space-exploration") and change.old_version ~= change.new_version then
        return false
      end
    end
  end
  return true
end

local function loaders_added(changes, active)
  local addition = changes[LOADERS]
  if type(addition) ~= "table" or addition.old_version ~= nil
      or addition.new_version ~= "0.2.11" or active[LOADERS] ~= addition.new_version then return false end
  for name, change in pairs(changes) do
    if name ~= LOADERS and (type(change) ~= "table" or type(change.old_version) ~= "string"
        or change.old_version ~= change.new_version or active[name] ~= change.new_version) then return false end
  end
  return true
end

local function values(force)
  local out = {force.worker_robots_speed_modifier, force.worker_robots_storage_bonus, force.artillery_range_modifier,
    force.get_gun_speed_modifier("artillery-shell"), force.get_gun_speed_modifier("laser"),
    force.get_ammo_damage_modifier("laser")}
  for index = 1, 6 do require_policy(finite(out[index]), "unavailable scripted field " .. index) end
  return out
end

local function recipe_unlocks_only(prototype)
  if type(prototype.effects) ~= "table" or prototype.max_level ~= prototype.level then return false end
  for _, effect in pairs(prototype.effects) do
    if effect.type ~= "unlock-recipe" or type(effect.recipe) ~= "string" then return false end
  end
  return true
end

local function needs_restoration(force)
  if not force or force.valid ~= true or force.name ~= "conquest" or force.ai_controllable ~= true
      or not finite(force.index) or force.index <= 0 or force.index % 1 ~= 0
      or game.forces[force.index] ~= force then return false end
  for _ in pairs(force.players) do return false end
  if force.current_research ~= nil or force.research_progress ~= 0 then return false end
  local queue = force.research_queue
  if queue ~= nil and type(queue) ~= "table" and type(queue) ~= "userdata" then return false end
  for _ in pairs(queue or {}) do return false end
  local readable, observed = pcall(values, force)
  if not readable then return false end
  for index = 1, 6 do
    if observed[index] ~= 0 then return false end
  end
  if type(force.set_gun_speed_modifier) ~= "function"
      or type(force.set_ammo_damage_modifier) ~= "function" then return false end
  local count, basics = 0, 0
  for name, row in pairs(force.technologies) do
    count = count + 1
    if count > TECHNOLOGY_LIMIT or type(name) ~= "string" or row.valid ~= true or row.name ~= name
        or not row.prototype or not finite(row.prototype.level) or row.level ~= row.prototype.level
        or row.saved_progress ~= 0 or type(row.researched) ~= "boolean" then return false end
    if BASIC[name] then
      if not row.researched then return false end
      basics = basics + 1
    end
    -- A finite recipe unlock such as night vision does not contribute to
    -- any of the six fields. Leave the researched row itself untouched.
    if row.researched and not recipe_unlocks_only(row.prototype) then return false end
  end
  return basics == 9
end

function M.preflight(event)
  local active = script and script.active_mods or {}
  if target.id ~= "f200" or active["space-exploration"] ~= "0.7.57" or active.base ~= "2.0.77"
      or active.Krastorio2 ~= nil or active["space-age"] ~= nil then return nil end
  if type(target.distribution_version) ~= "string" or target.distribution_version == ""
      or active[MIR] ~= target.distribution_version then return nil end
  local changes = type(event) == "table" and event.mod_changes
  if type(changes) ~= "table" then return nil end
  local change = changes[MIR]
  local historical = type(change) == "table" and change.new_version == target.distribution_version
    and (change.old_version == "4.7.20002" or change.old_version == "5.0.20017")
  -- SE authors these fixed NPC values independently of startup settings.
  -- Skip this optional repair when the native frame cannot prove it applies.
  -- An ambiguous NPC configuration must not stop an otherwise valid save.
  if historical then
    if not historical_origin(changes, active) then return nil end
  elseif not loaders_added(changes, active) or storage[RECOVERED_FORCE] == nil then
    return nil
  end
  local force = game.forces.conquest
  -- Adding AAI Loaders can reset all six native fields while MIR is unchanged.
  -- A prior successful restoration identifies the same force across saves.
  if not historical and force ~= storage[RECOVERED_FORCE] then return nil end
  if not needs_restoration(force) then return nil end
  return {force=force, event=event, used=false}
end

function M.apply(plan)
  if plan == nil then return end
  require_policy(type(plan) == "table" and plan.used == false, "plan is invalid or already consumed")
  local current = M.preflight(plan.event)
  plan.used = true
  if not current or current.force ~= plan.force then return end
  local force = plan.force
  force.worker_robots_speed_modifier, force.worker_robots_storage_bonus, force.artillery_range_modifier =
    DEFAULTS[1], DEFAULTS[2], DEFAULTS[3]
  force.set_gun_speed_modifier("artillery-shell", DEFAULTS[4])
  force.set_gun_speed_modifier("laser", DEFAULTS[5])
  force.set_ammo_damage_modifier("laser", DEFAULTS[6])
  local observed = values(force)
  for index = 1, 6 do require_policy(observed[index] == DEFAULTS[index], "scripted policy readback differs: " .. index) end
  storage[RECOVERED_FORCE] = force
end

return M

-- One published-source bridge for SE's scripted NPC policy, never research
-- credit. SE 0.7.57 scripts/system-forces.lua owns these six defaults and
-- reapplies them on its reset events. No other force or upstream state is ours.
-- An intentional third-party all-zero override is indistinguishable from
-- the demonstrated loss. This restores SE's canonical policy, not arbitrary
-- former offsets, and does not fingerprint the rest of the modpack.
local M = {}
local target = require("platform.target")
local MIR = "more-infinite-research"
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

local function origin(event, active)
  require_policy(active.base == "2.0.77" and active.Krastorio2 == nil and active["space-age"] == nil,
    "unsupported engine or provider")
  for name, change in pairs(event.mod_changes) do
    if name ~= MIR then
      require_policy(type(change) == "table" and type(change.old_version) == "string"
        and change.old_version == change.new_version and active[name] == change.new_version,
        "changed or removed mod: " .. tostring(name))
    end
  end
end

local function values(force)
  local out = {force.worker_robots_speed_modifier, force.worker_robots_storage_bonus, force.artillery_range_modifier,
    force.get_gun_speed_modifier("artillery-shell"), force.get_gun_speed_modifier("laser"),
    force.get_ammo_damage_modifier("laser")}
  for index = 1, 6 do require_policy(finite(out[index]), "unavailable scripted field " .. index) end
  return out
end

local function pristine(force)
  require_policy(force and force.valid == true and force.name == "conquest"
    and force.ai_controllable == true and finite(force.index) and force.index > 0 and force.index % 1 == 0
    and game.forces.conquest == force and game.forces[force.index] == force,
    "system-force identity differs")
  for _ in pairs(force.players) do require_policy(false, "system force has players") end
  require_policy(force.current_research == nil and force.research_progress == 0, "system force has current work")
  local queue = force.research_queue
  require_policy(queue == nil or type(queue) == "table" or type(queue) == "userdata", "research queue is unavailable")
  for _ in pairs(queue or {}) do require_policy(false, "system force has queued work") end
  local observed = values(force)
  for index = 1, 6 do require_policy(observed[index] == 0, "scripted vector is nonzero or mixed") end
  require_policy(type(force.set_gun_speed_modifier) == "function"
    and type(force.set_ammo_damage_modifier) == "function", "scripted setters are unavailable")
  local count, basics = 0, 0
  for name, row in pairs(force.technologies) do
    count = count + 1
    require_policy(count <= TECHNOLOGY_LIMIT, "technology observation exceeds bound")
    require_policy(type(name) == "string" and row.valid == true and row.name == name
      and row.prototype and finite(row.prototype.level) and row.level == row.prototype.level
      and row.saved_progress == 0, "invested or unavailable technology: " .. tostring(name))
    if BASIC[name] then
      basics = basics + 1
      require_policy(row.researched == true and row.prototype.max_level == row.prototype.level,
        "basic system technology differs: " .. name)
      require_policy(type(row.prototype.effects) == "table", "basic technology effects are unavailable: " .. name)
      for _, effect in pairs(row.prototype.effects) do
        require_policy(effect.type == "unlock-recipe" and type(effect.recipe) == "string",
          "basic technology has a native modifier: " .. name)
      end
    else
      require_policy(row.researched == false, "additional researched technology: " .. name)
    end
  end
  require_policy(basics == 9, "basic system technology set is incomplete: observed " .. basics .. ", expected 9")
end

function M.preflight(event)
  local active = script and script.active_mods or {}
  if target.id ~= "f200" or active["space-exploration"] ~= "0.7.57" then return nil end
  local change = type(event) == "table" and type(event.mod_changes) == "table" and event.mod_changes[MIR]
  if type(change) ~= "table" or change.old_version ~= "4.7.20002"
      or type(active[MIR]) ~= "string" or not active[MIR]:match("^5%.")
      or change.new_version ~= active[MIR] then return nil end
  require_policy(event.mod_startup_settings_changed == false, "startup settings changed or are unavailable")
  origin(event, active)
  local force = game.forces.conquest
  pristine(force)
  return {force=force, event=event, used=false}
end

function M.apply(plan)
  if plan == nil then return end
  require_policy(type(plan) == "table" and plan.used == false, "plan is invalid or already consumed")
  local current = M.preflight(plan.event)
  require_policy(current ~= nil and current.force == plan.force, "configuration or force changed after preflight")
  plan.used = true
  local force = plan.force
  force.worker_robots_speed_modifier, force.worker_robots_storage_bonus, force.artillery_range_modifier =
    DEFAULTS[1], DEFAULTS[2], DEFAULTS[3]
  force.set_gun_speed_modifier("artillery-shell", DEFAULTS[4])
  force.set_gun_speed_modifier("laser", DEFAULTS[5])
  force.set_ammo_damage_modifier("laser", DEFAULTS[6])
  local observed = values(force)
  for index = 1, 6 do require_policy(observed[index] == DEFAULTS[index], "scripted policy readback differs: " .. index) end
end

return M

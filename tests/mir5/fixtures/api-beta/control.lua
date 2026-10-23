if not script.active_mods["more-infinite-research"] then return end

local interface = "more-infinite-research.api.v1"
local technology_name = "mir-api-fixture-beta-cable-1"
local pending_stage = nil

local function fail(message)
  error("MIR 5 API beta fixture: " .. message, 2)
end

local function call(method, ...)
  if remote.interfaces[interface] == nil then fail("public runtime interface is absent") end
  return remote.call(interface, method, ...)
end

local function player_force()
  local force = game.forces.player
  if force == nil or force.valid == false then fail("player force is absent") end
  return force
end

local function assert_query(force)
  local version = call("get_version")
  if version.major ~= 1 then fail("public version differs") end
  version.major = 99
  if call("get_version").major ~= 1 then fail("version result is not detached") end
  local capabilities = call("get_capabilities")
  if capabilities.research_query ~= true then fail("research query capability is absent") end
  capabilities.research_query = false
  if call("get_capabilities").research_query ~= true then fail("capability result is not detached") end

  local before_modifier = force.manual_crafting_speed_modifier
  local native = force.technologies[technology_name]
  local status, code = call("get_research", force.index, technology_name)
  if code ~= nil or status == nil or status.name ~= technology_name or status.force_index ~= force.index
    or status.level ~= 1 or status.max_level ~= 1 or status.researched ~= false or status.enabled ~= native.enabled then
    fail("present technology query fields differ")
  end
  status.level = 99
  status.enabled = not native.enabled
  status.max_level = 99
  local detached = assert(call("get_research", force.index, technology_name))
  if detached.level ~= 1 or detached.researched ~= false
    or detached.enabled ~= native.enabled or detached.max_level ~= 1 then
    fail("research result is not detached")
  end
  if force.manual_crafting_speed_modifier ~= before_modifier then
    fail("public query changed the native force modifier")
  end
  local missing, missing_code = call("get_research", force.index, "mir-api-fixture-beta-missing")
  if missing ~= nil or missing_code ~= "technology_not_found" then fail("missing technology result differs") end
  local absent_force, absent_force_code = call("get_research", 2147483647, technology_name)
  if absent_force ~= nil or absent_force_code ~= "force_not_found" then fail("missing force result differs") end
  return detached
end

local function run(stage)
  local force = player_force()
  local technology = force.technologies[technology_name]
  if technology == nil then fail("immediate cable technology is absent") end
  local effects = technology.prototype.effects
  if #effects ~= 1 or effects[1].type ~= "change-recipe-productivity"
    or effects[1].recipe ~= "copper-cable" or effects[1].change ~= 0.01 then
    fail("native cable productivity effect differs")
  end
  local status = assert_query(force)
  pending_stage = {stage = stage, force_index = force.index, researched = status.researched,
    level = status.level, max_level = status.max_level,
    manual_crafting_speed_modifier = force.manual_crafting_speed_modifier}
end

local function emit_pending()
  if pending_stage == nil then return end
  local force = player_force()
  local status, code = call("get_research", force.index, technology_name)
  if code ~= nil or status == nil then fail("tick query differs") end
  local row = pending_stage
  row.tick = game.tick
  row.reload_level = status.level
  row.reload_manual_crafting_speed_modifier = force.manual_crafting_speed_modifier
  log("[MIR5_API_BETA] RESULT " .. helpers.table_to_json(row))
  pending_stage = nil
end

script.on_init(function()
  run("init")
  emit_pending()
end)

script.on_load(function()
  pending_stage = {stage = "load"}
end)

script.on_configuration_changed(function()
  run("configuration")
end)

script.on_event(defines.events.on_tick, emit_pending)

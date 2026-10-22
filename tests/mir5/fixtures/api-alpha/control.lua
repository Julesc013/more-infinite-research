local interface = "more-infinite-research.api.v1"
local alpha_name = "mir-api-fixture-alpha-1"
local prerequisite_name = "mir-api-fixture-alpha-2"
local pending_stage = nil

local function fail(message)
  error("MIR 5 API alpha fixture: " .. message, 2)
end

local function close(actual, expected)
  return math.abs(actual - expected) <= 0.000001
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

local function assert_public_query(force, expected_researched)
  local version = call("get_version")
  if version.major ~= 1 or version.minor ~= 0 then fail("public version differs") end
  version.major = 99
  if call("get_version").major ~= 1 then fail("version result is not detached") end

  local capabilities = call("get_capabilities")
  if capabilities.research_query ~= true then fail("research query capability is absent") end
  capabilities.research_query = false
  if call("get_capabilities").research_query ~= true then fail("capability result is not detached") end

  local before_modifier = force.manual_crafting_speed_modifier
  local native = force.technologies[alpha_name]
  local status, code = call("get_research", force.index, alpha_name)
  if code ~= nil or status == nil then fail("present technology query failed") end
  if status.name ~= alpha_name or status.force_index ~= force.index or status.level ~= 1
    or status.max_level ~= 1 or status.researched ~= expected_researched or status.enabled ~= native.enabled then
    fail("present technology query fields differ")
  end
  status.researched = not expected_researched
  status.level = 99
  status.enabled = not native.enabled
  status.max_level = 99
  local detached = assert(call("get_research", force.index, alpha_name))
  if detached.researched ~= expected_researched or detached.level ~= 1
    or detached.enabled ~= native.enabled or detached.max_level ~= 1 then
    fail("research result is not detached")
  end
  if force.manual_crafting_speed_modifier ~= before_modifier then
    fail("public query changed the native force modifier")
  end

  local missing, missing_code = call("get_research", force.index, "mir-api-fixture-alpha-missing")
  if missing ~= nil or missing_code ~= "technology_not_found" then fail("missing technology result differs") end
  local absent_force, absent_force_code = call("get_research", 2147483647, alpha_name)
  if absent_force ~= nil or absent_force_code ~= "force_not_found" then fail("missing force result differs") end
  return detached
end

local function run_initial()
  local force = player_force()
  local automation = force.technologies.automation
  local prerequisite = force.technologies[prerequisite_name]
  local technology = force.technologies[alpha_name]
  if automation == nil or prerequisite == nil or technology == nil then fail("alpha technologies are absent") end
  local effects = technology.prototype.effects
  if #effects ~= 1 or effects[1].type ~= "character-crafting-speed" or effects[1].modifier ~= 0.05 then
    fail("native character crafting speed effect differs")
  end
  local before = force.manual_crafting_speed_modifier
  assert_public_query(force, false)
  automation.researched = true
  prerequisite.researched = true
  technology.researched = true
  local after = force.manual_crafting_speed_modifier
  if not close(after, before + 0.05) then fail("native character crafting speed modifier differs") end
  local status = assert_public_query(force, true)
  pending_stage = {stage = "init", force_index = force.index, researched = status.researched,
    level = status.level, max_level = status.max_level, manual_crafting_speed_modifier = after}
end

local function emit_pending()
  if pending_stage == nil then return end
  local force = player_force()
  local status, code = call("get_research", force.index, alpha_name)
  if code ~= nil or status == nil or status.researched ~= true then fail("reload query differs") end
  local row = pending_stage
  row.tick = game.tick
  row.reload_researched = status.researched
  row.reload_level = status.level
  row.reload_manual_crafting_speed_modifier = force.manual_crafting_speed_modifier
  log("[MIR5_API_ALPHA] RESULT " .. helpers.table_to_json(row))
  pending_stage = nil
end

script.on_init(function()
  run_initial()
  emit_pending()
end)

script.on_load(function()
  pending_stage = {stage = "load"}
end)

script.on_configuration_changed(function()
  pending_stage = {stage = "configuration"}
end)

script.on_event(defines.events.on_tick, emit_pending)

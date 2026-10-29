-- Fresh CreateOnly native witness. No setters, save, storage or tick handlers.
local interface = "more-infinite-research.api.v1"
local single = "mir-api-boundary-single-1"
local names = {single, "mir-api-boundary-family-a-1", "mir-api-boundary-family-b-1"}
local function fail(message) error("[mir5-api-boundary] " .. message) end
script.on_init(function()
  local base = script.active_mods.base
  local expected = ({["2.0.77"] = "5.0.20000", ["2.1.23"] = "5.0.21000"})[base]
  if not expected or script.active_mods["more-infinite-research"] ~= expected then fail("engine or MIR differs") end
  if remote.interfaces[interface] == nil then fail("public interface absent") end
  local force = game.forces.player
  if not force or not force.valid then fail("player force absent") end
  local before = force.manual_crafting_speed_modifier
  local version = remote.call(interface, "get_version")
  if version.major ~= 1 or version.minor ~= 0 or version.product ~= expected then fail("runtime version differs") end
  for _, name in ipairs(names) do
    local native = force.technologies[name]
    if not native or native.researched or native.level ~= 1 then fail("fresh native row differs") end
    local status, code = remote.call(interface, "get_research", force.index, name)
    if code ~= nil or not status or status.name ~= name or status.researched ~= false
        or status.level ~= 1 or status.max_level ~= 1 or status.enabled ~= native.enabled then
      fail("public query differs")
    end
    status.researched, status.level = true, 99
    local again = remote.call(interface, "get_research", force.index, name)
    if not again or again.researched ~= false or again.level ~= 1 then fail("query result aliases state") end
  end
  local effects = force.technologies[single].prototype.effects
  if #effects ~= 1 or effects[1].type ~= "character-crafting-speed"
      or effects[1].modifier ~= 0.03125 then fail("single native effect differs") end
  if force.technologies["mir-api-boundary-refused-a-1"]
      or force.technologies["mir-api-boundary-refused-b-1"] then fail("refused family wrote native rows") end
  if force.manual_crafting_speed_modifier ~= before then fail("read-only witness changed native modifier") end
  log("[MIR5_API_BOUNDARY] RESULT " .. helpers.table_to_json({case = "api-boundary", stage = "init",
    status = "passed", base_version = base, mir_version = expected, native_rows = 3,
    single_effect = 0.03125, researched = false, refused_family_absent = true,
    native_query_detached = true, modifier_unchanged = true,
    qualification = "fresh-native-boundary-only", release_qualification = false}))
end)

-- Read-only native API witness for the one-time historical discovery repair.
local CASE = "planet-discovery-api-f210-2123"
local FIXTURE = "mir-fixture-planet-discovery-api"
local EXPECTED_MODS = {
  base = "2.1.23",
  ["elevated-rails"] = "2.1.23",
  quality = "2.1.23",
  recycler = "2.1.23",
  ["space-age"] = "2.1.23",
  [FIXTURE] = "0.1.0",
}
local LOCATIONS = {"nauvis", "vulcanus", "gleba", "fulgora", "aquilo"}

local function fail(message)
  error("[planet-discovery-api] " .. message)
end

local function ordered_active_mods()
  local rows = {}
  for name, version in pairs(script.active_mods) do
    rows[#rows + 1] = {name = name, version = version}
  end
  table.sort(rows, function(left, right) return left.name < right.name end)
  return rows
end

local function shape(value)
  local result = {lua_type = type(value)}
  if result.lua_type == "userdata" then result.native_object_name = value.object_name end
  return result
end

local function mapping_bounds(label, value)
  local names = {}
  for name in pairs(value) do
    if type(name) ~= "string" then fail(label .. " has a non-string key") end
    names[#names + 1] = name
  end
  table.sort(names)
  return {count = #names, first = names[1], last = names[#names]}
end

local function assert_mapping(label, value)
  local value_type = type(value)
  if value_type ~= "table" and value_type ~= "userdata" then
    fail(label .. " has unsupported type " .. value_type)
  end
end

local function assert_closure(active_mods)
  if #active_mods ~= 6 then fail("active mod closure count differs") end
  for _, row in ipairs(active_mods) do
    if EXPECTED_MODS[row.name] ~= row.version then fail("unexpected active mod " .. row.name) end
  end
  for name, version in pairs(EXPECTED_MODS) do
    if script.active_mods[name] ~= version then fail("missing active mod " .. name) end
  end
end

script.on_init(function()
  local forces = game.forces
  local player = forces and forces.player
  local technologies = player and player.technologies
  local locations = prototypes and prototypes.space_location
  local active_mods = ordered_active_mods()
  local shapes = {
    game_forces = shape(forces),
    player_force = shape(player),
    player_technologies = shape(technologies),
    space_locations = shape(locations),
  }
  log("[MIR_PLANET_DISCOVERY_API] SHAPES " .. helpers.table_to_json({
    case = CASE, stage = "init", scope = "native-api-shape-readonly-queries",
    active_mods = active_mods, shapes = shapes,
  }))

  assert_closure(active_mods)
  assert_mapping("game.forces", forces)
  if not player or player.valid == false then fail("player force is absent") end
  assert_mapping("player.technologies", technologies)
  assert_mapping("prototypes.space_location", locations)
  local query = player.is_space_location_unlocked
  if type(query) ~= "function" then fail("is_space_location_unlocked is absent") end
  for _, name in ipairs(LOCATIONS) do
    if locations[name] == nil then fail("space location is absent " .. name) end
  end

  local queries = {}
  for _, name in ipairs(LOCATIONS) do
    local value
    value = query(name)
    queries[#queries + 1] = {name = name, value = value, value_type = type(value)}
  end
  log("[MIR_PLANET_DISCOVERY_API] OBSERVED " .. helpers.table_to_json({
    case = CASE, stage = "init", scope = "native-api-shape-readonly-queries", queries = queries,
  }))
  for _, row in ipairs(queries) do
    if row.value_type ~= "boolean" then fail("space location query is not boolean " .. row.name) end
  end

  log("[MIR_PLANET_DISCOVERY_API] RESULT " .. helpers.table_to_json({
    case = CASE, stage = "init", status = "passed", scope = "native-api-shape-readonly-queries",
    active_mods = active_mods,
    observations = {shapes = shapes, queries = queries, bounds = {
      forces = mapping_bounds("game.forces", forces),
      technologies = mapping_bounds("player.technologies", technologies),
      locations = mapping_bounds("prototypes.space_location", locations),
    }},
  }))
end)

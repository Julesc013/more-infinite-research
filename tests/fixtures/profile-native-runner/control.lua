-- The existing read-only observer owns native expectations. This actor only
-- supplies a normal imported profile, saves once, and checks two cold reads.
local key, reported = "mir_profile_native_lifecycle", false
local expected = {
  ["mir-pipeline-extent-multiplier"] = 123.45,
  ["mir-prototype-productivity-cap"] = 4321.5,
  ["mir-prototype-efficiency-cap"] = -83.25,
  ["mir-prototype-pollution-cap"] = -91.125,
  ["mir-prototype-speed-floor"] = -75.5,
  ["mir-prototype-speed-cap"] = 1234.5,
  ["mir-prototype-quality-cap"] = 678.9,
  ["mir-recycling-return-chance"] = 12.34,
}

local function observe()
  local native = remote.call("mir_profile_native_witness", "observe")
  local wire = remote.call("more-infinite-research-settings", "export_string", {})
  assert(type(wire) == "string" and wire:sub(1, 8) == "MIRSET1:", "numeric profile export framing")
  local profile = helpers.json_to_table(assert(helpers.decode_string(wire:sub(9))))
  assert(type(profile) == "table" and type(profile.settings) == "table", "numeric profile export shape")
  local percentages = {}
  for name, value in pairs(expected) do
    assert(type(profile.settings[name]) == "number" and math.abs(profile.settings[name] - value) <= 0.000000001,
      "numeric profile effective percentage: " .. name)
    percentages[name] = profile.settings[name]
  end
  return {native = native, percentages = percentages}
end

local function same(actual, saved, depth)
  assert(depth <= 4 and type(actual) == type(saved), "numeric profile cold shape")
  if type(actual) ~= "table" then
    assert(actual == saved, "numeric profile cold value")
    return
  end
  local count = 0
  for name, value in pairs(actual) do
    count = count + 1
    assert(count <= 64 and saved[name] ~= nil, "numeric profile cold membership")
    same(value, saved[name], depth + 1)
  end
  for name in pairs(saved) do assert(actual[name] ~= nil, "numeric profile cold extra field") end
end

local function report(stage, observation)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case = "profile-native-numeric", stage = stage, status = "passed",
    witnesses = observation, ordinary_research_completion = false,
  }))
end

script.on_init(function()
  assert(storage[key] == nil, "numeric profile actor already initialized")
  storage[key] = {phase = "pending"}
end)
script.on_load(function() reported = false end)
script.on_event(defines.events.on_tick, function()
  if reported then return end
  local state = assert(storage[key], "numeric profile actor state absent")
  local observation = observe()
  if state.phase == "pending" then
    state.snapshot, state.phase = observation, "completed"
    report("initial", observation)
    game.server_save("mir5-native-complete")
  else
    assert(state.phase == "completed", "numeric profile actor phase")
    same(observation, state.snapshot, 0)
    report("reload", observation)
  end
  reported = true
end)

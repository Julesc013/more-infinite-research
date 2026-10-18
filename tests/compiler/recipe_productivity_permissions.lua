-- Source-bound control for the published recipe-productivity permission
-- contract. Mining-drill research emits its historical recipe effects, but
-- does not mutate upstream drill recipe eligibility. Existing Space Age
-- permission rows retain their published mutation behavior.
local permissions = MIR_RECIPE_PRODUCTIVITY_PERMISSIONS

local assertions = 0
local function check(value, message)
  assert(value, message)
  assertions = assertions + 1
end

local function apply(mods, recipes, streams)
  _G.mods = mods
  _G.data = {raw = {recipe = recipes}}
  _G.MIR_PERMISSION_STREAMS = streams
  _G.MIR_ENABLED_STREAMS = {}
  return permissions.apply()
end

do
  local recipes = {
    ["burner-mining-drill"] = {},
    ["electric-mining-drill"] = {normal = {}, expensive = {}},
    ["big-mining-drill"] = {},
    ["se-core-miner-drill"] = {allow_productivity = false}
  }
  local result = apply(
    {base = "2.1.21", ["space-age"] = "2.1.21", ["space-exploration"] = "0.7.61"},
    recipes,
    {research_mining_drill = _G.MIR_CURRENT_MINING_SPEC}
  )
  check(result.changed_count == 0,
    "the current parsed mining declaration grants no new drill productivity permissions")
  check(recipes["burner-mining-drill"].allow_productivity == nil
      and recipes["electric-mining-drill"].normal.allow_productivity == nil
      and recipes["electric-mining-drill"].expensive.allow_productivity == nil
      and recipes["big-mining-drill"].allow_productivity == nil
      and recipes["se-core-miner-drill"].allow_productivity == false,
    "native and Space Exploration drill prototype eligibility remains upstream-owned")
end

do
  local recipes = {
    ["capture-robot-rocket"] = {allow_productivity = false},
    ["ice-platform"] = {normal = {allow_productivity = false}},
    ["space-platform-foundation"] = {expensive = {allow_productivity = false}}
  }
  local result = apply(
    {base = "2.1.21", ["space-age"] = "2.1.21"},
    recipes,
    {
      research_capture_robot_rockets = _G.MIR_CURRENT_CAPTURE_SPEC,
      research_platform = _G.MIR_CURRENT_PLATFORM_SPEC
    }
  )
  check(result.changed_count == 3,
    "the three published Space Age productivity permission rows remain active")
  check(recipes["capture-robot-rocket"].allow_productivity == true
      and recipes["ice-platform"].normal.allow_productivity == true
      and recipes["space-platform-foundation"].expensive.allow_productivity == true,
    "published Space Age permission behavior remains the existing direct recipe declaration")
end

print("MIR-RECIPE-PRODUCTIVITY-PERMISSIONS-PASS " .. assertions)
return {assertions = assertions}

local science = require("__more-infinite-research__.prototypes.mir.capabilities.science_integration.science_packs")

local function fail(message)
  error("MIR generated prerequisite safety validation failed: " .. message)
end

local initial_status, initial_prerequisite = science.pack_production_status("mir-fixture-initial-science-pack")
if initial_status ~= "initial" or initial_prerequisite ~= nil then
  fail("already-enabled fixture science should have no inferred prerequisite.")
end

local fixture_pack = "mir-fixture-prerequisite-science-pack"
local fixture_status, fixture_prerequisite = science.pack_production_status(fixture_pack)
if fixture_status ~= "research" then
  fail("fixture science pack should require an enabled unlock technology, got " .. tostring(fixture_status) .. ".")
end
if fixture_prerequisite ~= "mir-fixture-custom-unlocker-a" then
  fail("deterministic unlock selection chose " .. tostring(fixture_prerequisite) .. ".")
end

local technologies = data.raw.technology or {}
local complete = {}

local function assert_reachable(name, visiting, path)
  if complete[name] then return end
  if visiting[name] then
    fail("prerequisite cycle: " .. table.concat(path, " -> ") .. " -> " .. name .. ".")
  end

  local technology = technologies[name]
  if not technology then fail("missing prerequisite " .. tostring(name) .. ".") end
  if technology.enabled == false then fail("disabled prerequisite " .. name .. ".") end

  visiting[name] = true
  table.insert(path, name)
  for _, prerequisite in ipairs(technology.prerequisites or {}) do
    assert_reachable(prerequisite, visiting, path)
  end
  table.remove(path)
  visiting[name] = nil
  complete[name] = true
end

local generated_count = 0
local fixture_pack_user_count = 0
for name, technology in pairs(technologies) do
  if string.match(name, "^recipe%-prod%-research_") then
    generated_count = generated_count + 1
    assert_reachable(name, {}, {})

    for _, ingredient in ipairs(((technology.unit or {}).ingredients) or {}) do
      local pack_name = ingredient.name or ingredient[1]
      local status = science.pack_production_status(pack_name)
      if status == "unreachable" then
        fail("generated technology " .. name .. " uses unreachable science pack " .. tostring(pack_name) .. ".")
      end
      if pack_name == fixture_pack then fixture_pack_user_count = fixture_pack_user_count + 1 end
    end
  end
end

if generated_count == 0 then fail("no generated stream technologies were found.") end
if fixture_pack_user_count == 0 then fail("the all-science scenario did not exercise the fixture science pack.") end

local science = require("__more-infinite-research__.prototypes.mir.capabilities.science_integration.science_packs")

local function fail(message)
  error("MIR generated prerequisite safety validation failed: " .. message)
end

if data.raw.technology["worker-robots-storage-4"] then
  fail("base extension was emitted from disabled worker-robots-storage-3.")
end
if data.raw.technology["worker-robots-storage-3"].enabled ~= false then
  fail("disabled base-extension anchor was unexpectedly re-enabled.")
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

for _, unreachable_pack in ipairs({
  "mir-fixture-self-lock-science-pack",
  "mir-fixture-cycle-science-pack-a",
  "mir-fixture-cycle-science-pack-b"
}) do
  local status = science.pack_production_status(unreachable_pack)
  if status ~= "unreachable" then
    fail(unreachable_pack .. " should be unreachable, got " .. tostring(status) .. ".")
  end
end

local no_mechanism_technology = data.raw.technology["mir-fixture-no-research-mechanism-unlocker"]
local saved_unit = no_mechanism_technology.unit
no_mechanism_technology.unit = nil
local mechanism_reason = science.technology_researchability_reason("mir-fixture-no-research-mechanism-unlocker")
no_mechanism_technology.unit = saved_unit
if mechanism_reason ~= "missing-research-mechanism" then
  fail("missing-mechanism unlocker reason was " .. tostring(mechanism_reason) .. ".")
end

if #science.researchable_unlockers_for_recipe("mir-fixture-initial-science-pack") ~= 0 then
  fail("initially enabled recipe retained inferred unlock prerequisites.")
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
local unreachable_pack_user_count = 0
local unreachable_packs = {
  ["mir-fixture-self-lock-science-pack"] = true,
  ["mir-fixture-cycle-science-pack-a"] = true,
  ["mir-fixture-cycle-science-pack-b"] = true
}
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
      if unreachable_packs[pack_name] then unreachable_pack_user_count = unreachable_pack_user_count + 1 end
    end
  end
end

if generated_count == 0 then fail("no generated stream technologies were found.") end
if fixture_pack_user_count == 0 then fail("the all-science scenario did not exercise the fixture science pack.") end
if unreachable_pack_user_count ~= 0 then fail("generated streams retained unreachable fixture science packs.") end

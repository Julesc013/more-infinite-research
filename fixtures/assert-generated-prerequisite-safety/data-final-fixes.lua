local function fail(message)
  error("MIR generated prerequisite safety validation failed: " .. message)
end

local function sorted_unlockers(recipe_name)
  local names = {}
  for technology_name, technology in pairs(data.raw.technology or {}) do
    if technology.enabled ~= false then
      for _, effect in ipairs(technology.effects or {}) do
        if effect.type == "unlock-recipe" and effect.recipe == recipe_name then
          names[#names + 1] = technology_name
          break
        end
      end
    end
  end
  table.sort(names)
  return names
end

local pack_status
local technology_reason
local pack_memo = {}
local pack_visiting = {}
local technology_visiting = {}

technology_reason = function(technology_name)
  local technology = (data.raw.technology or {})[technology_name]
  if not technology then return "missing-technology" end
  if technology.enabled == false then return "disabled-technology" end
  if not technology.unit then return "missing-research-mechanism" end
  if technology_visiting[technology_name] then return "technology-cycle" end

  technology_visiting[technology_name] = true
  for _, prerequisite in ipairs(technology.prerequisites or {}) do
    if technology_reason(prerequisite) then
      technology_visiting[technology_name] = nil
      return "unreachable-prerequisite"
    end
  end
  for _, ingredient in ipairs(technology.unit.ingredients or {}) do
    local pack_name = ingredient.name or ingredient[1]
    if pack_status(pack_name) == "unreachable" then
      technology_visiting[technology_name] = nil
      return "unreachable-science"
    end
  end
  technology_visiting[technology_name] = nil
  return nil
end

pack_status = function(pack_name)
  if pack_memo[pack_name] then return pack_memo[pack_name][1], pack_memo[pack_name][2] end
  local recipe = (data.raw.recipe or {})[pack_name]
  if pack_name == "space-science-pack" and not recipe then
    pack_memo[pack_name] = { "initial", nil }
    return "initial", nil
  end
  if not recipe then return "unreachable", nil end
  if recipe.enabled ~= false then
    pack_memo[pack_name] = { "initial", nil }
    return "initial", nil
  end
  if pack_visiting[pack_name] then return "unreachable", nil end
  pack_visiting[pack_name] = true
  for _, technology_name in ipairs(sorted_unlockers(pack_name)) do
    if not technology_reason(technology_name) then
      pack_visiting[pack_name] = nil
      pack_memo[pack_name] = { "research", technology_name }
      return "research", technology_name
    end
  end
  pack_visiting[pack_name] = nil
  pack_memo[pack_name] = { "unreachable", nil }
  return "unreachable", nil
end

local initial_status, initial_prerequisite = pack_status("mir-fixture-initial-science-pack")
if initial_status ~= "initial" or initial_prerequisite ~= nil then
  fail("already-enabled fixture science should have no inferred prerequisite.")
end

local fixture_pack = "mir-fixture-prerequisite-science-pack"
local fixture_status, fixture_prerequisite = pack_status(fixture_pack)
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
  local status = pack_status(unreachable_pack)
  if status ~= "unreachable" then
    fail(unreachable_pack .. " should be unreachable, got " .. tostring(status) .. ".")
  end
end

local no_mechanism_technology = data.raw.technology["mir-fixture-no-research-mechanism-unlocker"]
local saved_unit = no_mechanism_technology.unit
no_mechanism_technology.unit = nil
local mechanism_reason = technology_reason("mir-fixture-no-research-mechanism-unlocker")
no_mechanism_technology.unit = saved_unit
if mechanism_reason ~= "missing-research-mechanism" then
  fail("missing-mechanism unlocker reason was " .. tostring(mechanism_reason) .. ".")
end

if #sorted_unlockers("mir-fixture-initial-science-pack") ~= 0 then
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
      local status = pack_status(pack_name)
      if status == "unreachable" then
        fail("generated technology " .. name .. " uses unreachable science pack " .. tostring(pack_name) .. ".")
      end
      if pack_name == fixture_pack then fixture_pack_user_count = fixture_pack_user_count + 1 end
      if unreachable_packs[pack_name] then unreachable_pack_user_count = unreachable_pack_user_count + 1 end
    end
  end
end

if generated_count == 0 then fail("no generated stream technologies were found.") end
if unreachable_pack_user_count ~= 0 then fail("generated streams retained unreachable fixture science packs.") end

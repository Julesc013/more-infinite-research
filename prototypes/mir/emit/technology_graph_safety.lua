local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local science = require("prototypes.mir.capabilities.science_integration.science_packs")

local M = {}

local function ingredient_name(ingredient)
  if type(ingredient) == "string" then return ingredient end
  return ingredient and (ingredient.name or ingredient[1]) or nil
end

local function assert_reachable(name, complete, visiting, path)
  if complete[name] then return end
  if visiting[name] then
    error("MIR generated technology prerequisite cycle: " .. table.concat(path, " -> ") .. " -> " .. name .. ".", 3)
  end

  local technology = data_raw.technology(name)
  if not technology then
    error("MIR generated technology graph references missing technology " .. tostring(name) .. ".", 3)
  end
  if technology.enabled == false then
    error("MIR generated technology graph references disabled technology " .. name .. ".", 3)
  end

  visiting[name] = true
  table.insert(path, name)

  local prerequisites = {}
  for _, prerequisite in ipairs(technology.prerequisites or {}) do
    table.insert(prerequisites, prerequisite)
  end
  table.sort(prerequisites)
  for _, prerequisite in ipairs(prerequisites) do
    assert_reachable(prerequisite, complete, visiting, path)
  end

  table.remove(path)
  visiting[name] = nil
  complete[name] = true
end

local function assert_science_reachable(name, technology)
  local ingredients = ((technology or {}).unit or {}).ingredients or {}
  if #ingredients == 0 then
    error("MIR generated technology " .. name .. " has no research ingredients.", 3)
  end
  if not science.valid_research_ingredients(ingredients) then
    error("MIR generated technology " .. name .. " has no active lab accepting its complete science set.", 3)
  end

  for _, ingredient in ipairs(ingredients) do
    local pack_name = ingredient_name(ingredient)
    local status = science.pack_production_status(pack_name)
    if status == "unreachable" then
      error("MIR generated technology " .. name .. " uses unreachable science pack " .. tostring(pack_name) .. ".", 3)
    end
  end
end

function M.assert_registered_technologies()
  local complete = {}
  for _, name in ipairs(generated_registry.sorted_names()) do
    local technology = data_raw.technology(name)
    if not technology then
      error("MIR registered generated technology is missing: " .. name .. ".", 2)
    end
    if technology.enabled == false then
      error("MIR generated technology is disabled: " .. name .. ".", 2)
    end

    assert_reachable(name, complete, {}, {})
    assert_science_reachable(name, technology)
  end
end

return M

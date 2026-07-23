local deepcopy = require("prototypes.mir.core.deepcopy")
local operator_dsl = require("prototypes.mir.families.operator_dsl")
local recipe_facts = require("prototypes.mir.index.recipe_facts")

local M = {}

local function infer_seed_item(seed, fact)
  if seed.item then return seed.item end
  local names, seen = {}, {}
  for _, result in ipairs((fact and fact.results) or {}) do
    if result.type == "item" and result.name and not seen[result.name] then
      seen[result.name] = true
      table.insert(names, result.name)
    end
  end
  if #names == 1 then return names[1] end
  return nil
end

function M.candidates(rule, indexes, seeds)
  local by_key = {}
  local stream = operator_dsl.grouping_stream(rule.operators)
  for _, item_name in ipairs(operator_dsl.candidate_items(rule.operators, indexes)) do
    for _, recipe_name in ipairs(indexes.recipes_by_output[item_name] or {}) do
      by_key[recipe_name .. "\0" .. item_name] = {
        recipe = recipe_name, item = item_name, source = "structural"
      }
    end
  end
  for _, seed in ipairs(seeds or {}) do
    if seed.family == rule.id and seed.stream == stream then
      local fact = recipe_facts.view(seed.recipe)
      local item_name = infer_seed_item(seed, fact)
      if not item_name then
        error("CompatibilityPack candidate seed requires an exact item for ambiguous recipe " .. seed.recipe, 2)
      end
      by_key[seed.recipe .. "\0" .. item_name] = {
        recipe = seed.recipe,
        item = item_name,
        source = "compatibility-pack-seed",
        pack = seed.pack,
        evidence = deepcopy(seed.evidence),
        change = seed.change,
        tier = seed.tier
      }
    end
  end
  local out = {}
  for _, candidate in pairs(by_key) do table.insert(out, deepcopy(candidate)) end
  table.sort(out, function(left, right)
    if left.recipe ~= right.recipe then return left.recipe < right.recipe end
    return left.item < right.item
  end)
  return out
end

return M

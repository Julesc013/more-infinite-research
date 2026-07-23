local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

local function sorted(values)
  local out = {}
  for _, value in ipairs(values or {}) do table.insert(out, value) end
  table.sort(out)
  return out
end

local function ingredient_name(ingredient)
  return type(ingredient) == "table" and (ingredient.name or ingredient[1]) or ingredient
end

function M.new(technologies)
  local nodes = {}
  for name, technology in pairs(technologies or {}) do
    local ingredients = {}
    for _, ingredient in ipairs(((technology or {}).unit or {}).ingredients or {}) do
      table.insert(ingredients, ingredient_name(ingredient))
    end
    table.sort(ingredients)
    table.insert(nodes, {
      name = name,
      enabled = technology.enabled ~= false,
      prerequisites = sorted(technology.prerequisites),
      research_trigger = technology.research_trigger ~= nil,
      science_packs = ingredients,
      has_research_count = technology.unit ~= nil
        and (technology.unit.count ~= nil or technology.unit.count_formula ~= nil)
    })
  end
  table.sort(nodes, function(left, right) return left.name < right.name end)
  local snapshot = {schema = 1, nodes = nodes}
  snapshot.graph_fingerprint = fingerprint.of({schema = snapshot.schema, nodes = snapshot.nodes})
  return snapshot
end

function M.technology_map(snapshot)
  local out = {}
  for _, node in ipairs(snapshot.nodes or {}) do out[node.name] = deepcopy(node) end
  return out
end

return M

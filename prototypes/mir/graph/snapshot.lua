local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local technology_views = setmetatable({}, {__mode = "k"})

local function sorted(values)
  local out = {}
  for _, value in ipairs(values or {}) do table.insert(out, value) end
  table.sort(out)
  return out
end

local function ingredient_name(ingredient)
  return type(ingredient) == "table" and (ingredient.name or ingredient[1]) or ingredient
end

function M.new(technologies, options)
  options = options or {}
  local nodes = {}
  local technology_view = {}
  for name, technology in pairs(technologies or {}) do
    local ingredients = {}
    for _, ingredient in ipairs(((technology or {}).unit or {}).ingredients or {}) do
      table.insert(ingredients, ingredient_name(ingredient))
    end
    table.sort(ingredients)
    local node = {
      name = name,
      enabled = technology.enabled ~= false,
      prerequisites = options.prerequisites_by_name
        and options.prerequisites_by_name[name]
        or sorted(technology.prerequisites),
      research_trigger = technology.research_trigger ~= nil,
      science_packs = ingredients,
      has_research_count = technology.unit ~= nil
        and (technology.unit.count ~= nil or technology.unit.count_formula ~= nil)
    }
    table.insert(nodes, node)
    technology_view[name] = node
  end
  table.sort(nodes, function(left, right) return left.name < right.name end)
  local snapshot = {schema = 1, nodes = nodes}
  snapshot.graph_fingerprint = fingerprint.of({schema = snapshot.schema, nodes = snapshot.nodes})
  technology_views[snapshot] = technology_view
  return snapshot
end

function M.technology_view(snapshot)
  local view = technology_views[snapshot]
  if view then return view end
  view = {}
  for _, node in ipairs(snapshot.nodes or {}) do view[node.name] = node end
  technology_views[snapshot] = view
  return view
end

function M.technology_map(snapshot)
  local out = {}
  for name, node in pairs(M.technology_view(snapshot)) do out[name] = deepcopy(node) end
  return out
end

local function same_array(left, right)
  if type(left) ~= "table" or type(right) ~= "table" or #left ~= #right then return false end
  for index = 1, #left do if left[index] ~= right[index] then return false end end
  return true
end

function M.same(left, right)
  if type(left) ~= "table" or type(right) ~= "table"
    or left.schema ~= right.schema or #(left.nodes or {}) ~= #(right.nodes or {}) then
    return false
  end
  for index, expected in ipairs(left.nodes or {}) do
    local actual = right.nodes[index]
    if type(actual) ~= "table"
      or expected.name ~= actual.name
      or expected.enabled ~= actual.enabled
      or expected.research_trigger ~= actual.research_trigger
      or expected.has_research_count ~= actual.has_research_count
      or not same_array(expected.prerequisites or {}, actual.prerequisites or {})
      or not same_array(expected.science_packs or {}, actual.science_packs or {}) then
      return false
    end
  end
  return true
end

return M

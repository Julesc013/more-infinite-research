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

local function node_from_prototype(name, technology, prerequisites)
  local ingredients = {}
  for _, ingredient in ipairs(((technology or {}).unit or {}).ingredients or {}) do
    table.insert(ingredients, ingredient_name(ingredient))
  end
  table.sort(ingredients)
  return {
    name = name,
    enabled = technology.enabled ~= false,
    prerequisites = prerequisites or sorted(technology.prerequisites),
    research_trigger = technology.research_trigger ~= nil,
    science_packs = ingredients,
    has_research_count = technology.unit ~= nil
      and (technology.unit.count ~= nil or technology.unit.count_formula ~= nil)
  }
end

local function same_array(left, right)
  if type(left) ~= "table" or type(right) ~= "table" or #left ~= #right then return false end
  for index = 1, #left do if left[index] ~= right[index] then return false end end
  return true
end

local function same_node(left, right)
  return type(left) == "table" and type(right) == "table"
    and left.name == right.name
    and left.enabled == right.enabled
    and left.research_trigger == right.research_trigger
    and left.has_research_count == right.has_research_count
    and same_array(left.prerequisites or {}, right.prerequisites or {})
    and same_array(left.science_packs or {}, right.science_packs or {})
end

local function replacement_prerequisites(prerequisites, old_name, replacements)
  local out, seen = {}, {}
  for _, name in ipairs(prerequisites or {}) do
    if name == old_name then
      for _, replacement in ipairs(replacements or {}) do
        if not seen[replacement] then
          seen[replacement] = true
          table.insert(out, replacement)
        end
      end
    elseif not seen[name] then
      seen[name] = true
      table.insert(out, name)
    end
  end
  table.sort(out)
  return out
end

local function snapshot_from_nodes(nodes)
  table.sort(nodes, function(left, right) return left.name < right.name end)
  local snapshot = {schema = 1, nodes = nodes}
  snapshot.graph_fingerprint = fingerprint.of({schema = snapshot.schema, nodes = snapshot.nodes})
  local view = {}
  for _, node in ipairs(nodes) do view[node.name] = node end
  technology_views[snapshot] = view
  return snapshot
end

function M.new(technologies, options)
  options = options or {}
  local nodes = {}
  local technology_view = {}
  local function append(name, technology)
    local node = node_from_prototype(name, technology,
      options.prerequisites_by_name and options.prerequisites_by_name[name] or nil)
    table.insert(nodes, node)
    technology_view[name] = node
  end
  if options.sorted_names then
    for _, name in ipairs(options.sorted_names) do append(name, technologies[name]) end
  else
    for name, technology in pairs(technologies or {}) do append(name, technology) end
    table.sort(nodes, function(left, right) return left.name < right.name end)
  end
  local snapshot = snapshot_from_nodes(nodes)
  technology_views[snapshot] = technology_view
  return snapshot
end

-- Project the exact normalized graph that a validated sequence of technology
-- replacements is allowed to realize. Every removed node and every dependent
-- prerequisite rewrite must match the journal's before/after evidence.
function M.apply_replacement_journal(snapshot, entries)
  if type(snapshot) ~= "table" or snapshot.schema ~= 1 or type(entries) ~= "table" then
    error("MIR graph replacement projection requires a schema-1 snapshot and journal entries.", 2)
  end
  local by_name = {}
  for _, node in ipairs(snapshot.nodes or {}) do by_name[node.name] = deepcopy(node) end

  for _, entry in ipairs(entries) do
    local old_node = by_name[entry.old_technology]
    if not old_node then
      error("MIR graph replacement journal removes an absent qualified node: "
        .. tostring(entry.old_technology) .. ".", 2)
    end
    if fingerprint.of(old_node) ~= entry.old_graph_node_fingerprint then
      error("MIR graph replacement journal old-node authority differs for "
        .. tostring(entry.old_technology) .. ".", 2)
    end
    for _, replacement in ipairs(entry.replacement_technologies or {}) do
      if not by_name[replacement] then
        error("MIR graph replacement journal references an absent qualified replacement: "
          .. tostring(replacement) .. ".", 2)
      end
    end

    local expected_dependents = {}
    for name, node in pairs(by_name) do
      if name ~= entry.old_technology then
        for _, prerequisite in ipairs(node.prerequisites or {}) do
          if prerequisite == entry.old_technology then
            expected_dependents[name] = node
            break
          end
        end
      end
    end
    local journal_dependents = {}
    for _, row in ipairs(entry.rewired_dependents or {}) do
      if journal_dependents[row.technology_name] then
        error("MIR graph replacement journal repeats dependent " .. row.technology_name .. ".", 2)
      end
      journal_dependents[row.technology_name] = row
    end
    for name in pairs(expected_dependents) do
      if not journal_dependents[name] then
        error("MIR graph replacement journal omits dependent " .. name .. ".", 2)
      end
    end
    for name, row in pairs(journal_dependents) do
      local node = expected_dependents[name]
      if not node then
        error("MIR graph replacement journal declares an unexpected dependent " .. name .. ".", 2)
      end
      if not same_array(node.prerequisites or {}, row.before_prerequisites or {}) then
        error("MIR graph replacement journal before-state differs for dependent " .. name .. ".", 2)
      end
      local projected = replacement_prerequisites(
        row.before_prerequisites, entry.old_technology, entry.replacement_technologies)
      if not same_array(projected, row.after_prerequisites or {}) then
        error("MIR graph replacement journal after-state is not the declared exact rewrite for dependent "
          .. name .. ".", 2)
      end
      node.prerequisites = deepcopy(row.after_prerequisites)
    end
    by_name[entry.old_technology] = nil
  end

  local nodes = {}
  for _, node in pairs(by_name) do table.insert(nodes, node) end
  return snapshot_from_nodes(nodes)
end

-- Prove a live prototype registry has the exact normalized node projection of
-- a trusted snapshot without allocating and canonicalizing a second snapshot.
-- A mismatch returns false so the caller can build the complete actual
-- snapshot on the exceptional diagnostic path.
function M.matches_prototypes(snapshot, technologies)
  if type(snapshot) ~= "table" or snapshot.schema ~= 1 or type(technologies) ~= "table" then
    return false
  end
  local count = 0
  for _ in pairs(technologies) do count = count + 1 end
  if count ~= #(snapshot.nodes or {}) then return false end
  for _, expected in ipairs(snapshot.nodes or {}) do
    local technology = technologies[expected.name]
    if not technology or not same_node(expected, node_from_prototype(expected.name, technology)) then
      return false
    end
  end
  return true
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

function M.same(left, right)
  if type(left) ~= "table" or type(right) ~= "table"
    or left.schema ~= right.schema or #(left.nodes or {}) ~= #(right.nodes or {}) then
    return false
  end
  for index, expected in ipairs(left.nodes or {}) do
    local actual = right.nodes[index]
    if not same_node(expected, actual) then
      return false
    end
  end
  return true
end

return M

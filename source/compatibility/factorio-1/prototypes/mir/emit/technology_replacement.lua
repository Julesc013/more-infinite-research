local data_raw = require("prototypes.mir.platform.factorio.data_raw")

local M = {}

local function normalized_replacements(replacements)
  if type(replacements) == "string" then replacements = { replacements } end
  local out, seen = {}, {}
  for _, name in ipairs(replacements or {}) do
    if name and not seen[name] then
      seen[name] = true
      table.insert(out, name)
    end
  end
  return out
end

local function replacement_prerequisites(prerequisites, old_name, replacements)
  local out, seen = {}, {}
  for _, name in ipairs(prerequisites or {}) do
    if name == old_name then
      for _, replacement in ipairs(replacements) do
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
  return out
end

local function proposed_prerequisites(technologies, old_name, replacements)
  local proposed = {}
  for name, technology in pairs(technologies) do
    if name ~= old_name then
      proposed[name] = replacement_prerequisites(technology.prerequisites, old_name, replacements)
    end
  end
  return proposed
end

local function graph_cycle(proposed)
  local complete, visiting = {}, {}
  local function visit(name, path)
    if complete[name] then return nil end
    if visiting[name] then
      local cycle = {}
      for _, value in ipairs(path) do table.insert(cycle, value) end
      table.insert(cycle, name)
      return table.concat(cycle, " -> ")
    end
    if not proposed[name] then return nil end

    visiting[name] = true
    table.insert(path, name)
    for _, prerequisite in ipairs(proposed[name]) do
      local cycle = visit(prerequisite, path)
      if cycle then return cycle end
    end
    table.remove(path)
    visiting[name] = nil
    complete[name] = true
    return nil
  end

  local names = {}
  for name, _ in pairs(proposed) do table.insert(names, name) end
  table.sort(names)
  for _, name in ipairs(names) do
    local cycle = visit(name, {})
    if cycle then return cycle end
  end
  return nil
end

function M.replace_technology(old_name, replacements)
  local technologies = data_raw.prototypes("technology")
  if not old_name or not technologies[old_name] then return false, "old_technology_missing" end

  local replacement_names = normalized_replacements(replacements)
  if #replacement_names == 0 then return false, "replacement_missing" end
  for _, name in ipairs(replacement_names) do
    if name == old_name then return false, "replacement_is_old_technology" end
    if not technologies[name] then return false, "replacement_technology_missing:" .. tostring(name) end
  end

  local proposed = proposed_prerequisites(technologies, old_name, replacement_names)
  local cycle = graph_cycle(proposed)
  if cycle then return false, "replacement_cycle:" .. cycle end

  for name, prerequisites in pairs(proposed) do
    local technology = technologies[name]
    if technology then
      local referenced_old = false
      for _, prerequisite in ipairs(technology.prerequisites or {}) do
        if prerequisite == old_name then referenced_old = true break end
      end
      if referenced_old then
        technology.prerequisites = #prerequisites > 0 and prerequisites or nil
      end
    end
  end
  technologies[old_name] = nil
  return true
end

function M.remove_technology_if_unreferenced(name)
  local technologies = data_raw.prototypes("technology")
  if not name or not technologies[name] then return false, "technology_missing" end
  for dependent_name, technology in pairs(technologies) do
    for _, prerequisite in ipairs(technology.prerequisites or {}) do
      if prerequisite == name then
        return false, "technology_is_referenced_by:" .. dependent_name
      end
    end
  end
  technologies[name] = nil
  return true
end

return M

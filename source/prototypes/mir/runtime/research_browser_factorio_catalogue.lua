-- Factorio port for the portable research DTO surface. This is the only
-- browser-surface module that reads force technologies or prototype fields.
local M = {schema = 1, catalogue_limit = 30000}

local function available(technology)
  if not technology.enabled or technology.researched or technology.prototype.research_trigger then return false end
  for _, prerequisite in pairs(technology.prerequisites) do
    if not prerequisite.researched then return false end
  end
  return true
end

local function infinite(technology)
  local maximum = technology.prototype.max_level
  return maximum == "infinite" or (type(maximum) == "number" and maximum >= 4294967295)
end

-- The returned value contains plain scalar copies only. MIR facts are not
-- read here and can be omitted entirely by a non-MIR consumer.
function M.snapshot(force)
  if not force or not force.valid then return nil, "invalid-force" end
  local names, queued = {}, {}
  for _, technology in ipairs(force.research_queue or {}) do queued[technology.name] = true end
  for name in pairs(force.technologies) do
    names[#names + 1] = name
    if #names > M.catalogue_limit then return nil, "catalogue-limit" end
  end
  table.sort(names)
  local rows = {}
  for _, name in ipairs(names) do
    local technology = force.technologies[name]
    if technology then
      rows[#rows + 1] = {
        key = name,
        available = available(technology),
        researched = technology.researched == true,
        queued = queued[name] == true,
        infinite = infinite(technology)
      }
    end
  end
  return {schema = M.schema, kind = "portable-factorio-research-catalogue", rows = rows}
end

return M

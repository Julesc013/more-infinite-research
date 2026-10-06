-- Factorio port for the portable research DTO surface. This is the only
-- browser-surface module that reads force technologies or prototype fields.
local M = {schema = 1, catalogue_limit = 30000}
local progression_depth_limit = 128
-- These are prototype-derived facts. Keep them outside saved state and rebuild
-- after a script reload; each snapshot still reads force-local research state.
local static_by_force = {}

function M.forget_force(index)
  if type(index) == "number" and index > 0 and index == math.floor(index) then
    static_by_force[index] = nil
  end
end

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

-- Preserve the native technology ordering where one exists, while giving the
-- host a deterministic progression fallback. The capped walk keeps copied
-- catalogue work bounded even when a third-party technology graph is unusual.
local function progression_for(technologies, name, cache, visiting, depth)
  local known = cache[name]
  if known ~= nil then return known end
  if depth >= progression_depth_limit or visiting[name] then return progression_depth_limit end
  local technology = technologies[name]
  if not technology then return 0 end
  visiting[name] = true
  local result = 0
  for _, prerequisite in pairs(technology.prerequisites) do
    result = math.max(result, math.min(progression_depth_limit,
      progression_for(technologies, prerequisite.name, cache, visiting, depth + 1) + 1))
  end
  visiting[name] = nil
  cache[name] = result
  return result
end

local function native_order(technology)
  local order = technology.prototype.order
  return type(order) == "string" and string.sub(order, 1, 1024) or ""
end

local function static_catalogue(force)
  local index = force.index
  local cached = type(index) == "number" and static_by_force[index] or nil
  if cached and cached.force_name == force.name then return cached end
  local names = {}
  for name in pairs(force.technologies) do
    names[#names + 1] = name
    if #names > M.catalogue_limit then return nil, "catalogue-limit" end
  end
  table.sort(names)
  local progression, visiting = {}, {}
  for _, name in ipairs(names) do
    progression[name] = progression_for(force.technologies, name, progression, visiting, 0)
  end
  local rows = {}
  for _, name in ipairs(names) do
    local technology = force.technologies[name]
    if technology then
      rows[#rows + 1] = {
        key = name,
        infinite = infinite(technology),
        native_order = native_order(technology),
        progression = progression[name]
      }
    end
  end
  local result = {force_name = force.name, rows = rows}
  if type(index) == "number" then static_by_force[index] = result end
  return result
end

-- The returned value contains plain scalar copies only. MIR facts are not
-- read here and can be omitted entirely by a non-MIR consumer.
function M.snapshot(force)
  if not force or not force.valid then return nil, "invalid-force" end
  local static, reason = static_catalogue(force)
  if not static then return nil, reason end
  local queued, rows = {}, {}
  for _, technology in ipairs(force.research_queue or {}) do queued[technology.name] = true end
  for _, fact in ipairs(static.rows) do
    local technology = force.technologies[fact.key]
    if technology then
      rows[#rows + 1] = {
        key = fact.key,
        available = available(technology),
        researched = technology.researched == true,
        queued = queued[fact.key] == true,
        infinite = fact.infinite,
        native_order = fact.native_order,
        progression = fact.progression
      }
    end
  end
  return {schema = M.schema, kind = "portable-factorio-research-catalogue", rows = rows}
end

return M

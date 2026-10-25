-- Explicit external prerequisite repairs recovered from the published 4.7.3
-- compatibility registry. These are named F200/F210 edges, never a general
-- external-mod repair mechanism.
local M = {}

local SILVER = "angels-silver-smelting-1"
local ASTROPONICS = "astroponics"
local SPACE = "space-science-pack"
local ANGEL_REPAIR_ID = "angels-disabled-silver-modules-prerequisite"
local ASTROPONICS_REPAIR_ID = "muluna-astroponics-space-science-cycle"

local function supported_target(target)
  return type(target) == "table" and (target.id == "f200" or target.id == "f210")
end

local function active(active_mods, name)
  return type(active_mods[name]) == "string" and active_mods[name] ~= ""
end

local function contains(prerequisites, name)
  if type(prerequisites) ~= "table" then return false end
  for _, value in ipairs(prerequisites) do
    if value == name then return true end
  end
  return false
end

-- Return a fresh list only where the named edge exists. This keeps every
-- other prototype and every non-matching prerequisite-list identity intact.
local function without(prerequisites, name)
  if type(prerequisites) ~= "table" then return nil end
  local selected, removed = {}, false
  for _, value in ipairs(prerequisites) do
    if value == name then removed = true
    else selected[#selected + 1] = value end
  end
  if not removed then return nil end
  return #selected > 0 and selected or false
end

local function repair_angel(technologies)
  local modules, silver = technologies.modules, technologies[SILVER]
  if type(modules) ~= "table" or modules.enabled == false or type(silver) ~= "table"
      or silver.enabled ~= false then return false end
  local prerequisites = without(modules.prerequisites, SILVER)
  if prerequisites == nil then return false end
  modules.prerequisites = prerequisites or nil
  return true
end

-- The published repair accepted every finite prerequisite path from the
-- named space technology back to Astroponics. Keep that one proof local: no
-- raw-table scan, recursive walk, sort, researchability check or planner.
local function reaches_astroponics(technologies)
  local queue, visited, head = {SPACE}, {[SPACE] = true}, 1
  while head <= #queue do
    local name = queue[head]
    head = head + 1
    if name == ASTROPONICS then return true end
    local technology = technologies[name]
    local prerequisites = type(technology) == "table" and technology.prerequisites or nil
    if type(prerequisites) == "table" then
      for _, prerequisite in ipairs(prerequisites) do
        if type(prerequisite) == "string" and not visited[prerequisite] then
          visited[prerequisite] = true
          queue[#queue + 1] = prerequisite
        end
      end
    end
  end
  return false
end

local function repair_astroponics(technologies)
  local astroponics = technologies[ASTROPONICS]
  if type(astroponics) ~= "table" or not contains(astroponics.prerequisites, SPACE)
      or not reaches_astroponics(technologies) then return false end
  local prerequisites = without(astroponics.prerequisites, SPACE)
  if prerequisites == nil then return false end
  astroponics.prerequisites = prerequisites or nil
  return true
end

local function report_applied(report, id, technology, prerequisite)
  if type(report) == "function" then
    report("[more-infinite-research] Repaired " .. id .. ": removed " .. technology .. " -> " .. prerequisite .. ".")
  end
end

function M.apply(raw, active_mods, target, report)
  -- Historical editions and inactive optional contributions do not inspect
  -- data.raw or load this module from the data-stage entry point.
  if not supported_target(target) then return 0 end
  local angel_active = active(active_mods, "angelssmelting")
  local astroponics_active = active(active_mods, ASTROPONICS) and active(active_mods, "planet-muluna")
  if not angel_active and not astroponics_active then return 0 end
  if type(raw) ~= "table" or type(raw.technology) ~= "table" then return 0 end

  local repaired = 0
  if angel_active and repair_angel(raw.technology) then
    repaired = repaired + 1
    report_applied(report, ANGEL_REPAIR_ID, "modules", SILVER)
  end
  if astroponics_active and repair_astroponics(raw.technology) then
    repaired = repaired + 1
    report_applied(report, ASTROPONICS_REPAIR_ID, ASTROPONICS, SPACE)
  end
  return repaired
end

return M

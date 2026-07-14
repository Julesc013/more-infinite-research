local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local D = require("prototypes.mir.report.diagnostics_sink")

local M = {}

local REPAIRS = {
  {
    id = "muluna-astroponics-space-science-cycle",
    required_mods = {"astroponics", "planet-muluna"},
    technology = "astroponics",
    remove_prerequisite = "space-science-pack",
    reverse_path_start = "space-science-pack"
  }
}

local function has_prerequisite(technology, prerequisite)
  for _, name in ipairs((technology and technology.prerequisites) or {}) do
    if name == prerequisite then return true end
  end
  return false
end

local function all_mods_active(active_mods, required)
  for _, name in ipairs(required or {}) do
    if not active_mods[name] then return false end
  end
  return true
end

local function reaches(technologies, start_name, target_name)
  local pending, visited = {start_name}, {}
  while #pending > 0 do
    local name = table.remove(pending)
    if name == target_name then return true end
    if not visited[name] then
      visited[name] = true
      local prerequisites = {}
      for _, prerequisite in ipairs((technologies[name] and technologies[name].prerequisites) or {}) do
        table.insert(prerequisites, prerequisite)
      end
      table.sort(prerequisites, function(a, b) return a > b end)
      for _, prerequisite in ipairs(prerequisites) do table.insert(pending, prerequisite) end
    end
  end
  return false
end

function M.plan(technologies, active_mods)
  local operations = {}
  for _, repair in ipairs(REPAIRS) do
    local technology = technologies[repair.technology]
    if all_mods_active(active_mods or {}, repair.required_mods)
      and has_prerequisite(technology, repair.remove_prerequisite)
      and reaches(technologies, repair.reverse_path_start, repair.technology) then
      table.insert(operations, {
        id = repair.id,
        technology = repair.technology,
        remove_prerequisite = repair.remove_prerequisite,
        evidence = table.concat(repair.required_mods, "+") .. ":mutual-prerequisite-path"
      })
    end
  end
  return operations
end

function M.apply_plan(operations, technologies)
  for _, operation in ipairs(operations or {}) do
    local technology = technologies[operation.technology]
    local prerequisites = {}
    for _, prerequisite in ipairs((technology and technology.prerequisites) or {}) do
      if prerequisite ~= operation.remove_prerequisite then table.insert(prerequisites, prerequisite) end
    end
    technology.prerequisites = #prerequisites > 0 and prerequisites or nil
  end
end

function M.apply()
  local technologies = data_raw.prototypes("technology")
  local operations = M.plan(technologies, mods or {})
  M.apply_plan(operations, technologies)
  for _, operation in ipairs(operations) do
    log("[more-infinite-research] Repaired external technology prerequisite cycle " .. operation.id
      .. " by removing " .. operation.technology .. " -> " .. operation.remove_prerequisite .. ".")
    D.compatibility_plan({
      key = operation.id,
      status = "repaired",
      reason = "external_technology_prerequisite_cycle",
      technology = operation.technology,
      prerequisites = operation.remove_prerequisite,
      evidence = operation.evidence
    })
  end
  return operations
end

return M

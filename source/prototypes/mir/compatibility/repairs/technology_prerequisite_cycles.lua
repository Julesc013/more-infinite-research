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

-- Classic invokes this exact repair before declared planning.  The full
-- compiler keeps the historical unbounded path below; Classic is deliberately
-- bounded because an external prerequisite graph is not its support surface.
local CLASSIC_LIMITS = {
  visits = 128,
  edges = 256,
  name_bytes = 4096,
  array_entries = 256,
  prerequisites_per_technology = 64,
  name_bytes_per_value = 256
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

-- Planned operations are a transport for this module's declared repair, never
-- authority to mutate a caller-selected technology or prerequisite edge.
local function declared_repair_for_operation(operation)
  if type(operation) ~= "table" then return nil end
  for _, repair in ipairs(REPAIRS) do
    if operation.id == repair.id
      and operation.technology == repair.technology
      and operation.remove_prerequisite == repair.remove_prerequisite
      and operation.evidence == table.concat(repair.required_mods, "+") .. ":mutual-prerequisite-path" then
      return repair
    end
  end
  return nil
end

-- Historical Full behavior.  Do not route an options-omitted caller through
-- Classic's bounded representation: Full remains the existing repair API.
local function legacy_reaches(technologies, start_name, target_name)
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

local function legacy_plan(technologies, active_mods)
  local operations = {}
  for _, repair in ipairs(REPAIRS) do
    local technology = technologies[repair.technology]
    if all_mods_active(active_mods or {}, repair.required_mods)
      and has_prerequisite(technology, repair.remove_prerequisite)
      and legacy_reaches(technologies, repair.reverse_path_start, repair.technology) then
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

local function new_classic_budget()
  return {
    limits = CLASSIC_LIMITS,
    visits = 0,
    edges = 0,
    name_bytes = 0,
    array_entries = 0,
    reason = nil
  }
end

local function incomplete(budget, reason)
  if budget.reason == nil then budget.reason = reason end
  return false
end

local function consume(budget, field, amount, reason)
  if budget[field] + amount > budget.limits[field] then return incomplete(budget, reason) end
  budget[field] = budget[field] + amount
  return true
end

local function bounded_name(name, budget)
  if type(name) ~= "string" or name == "" or #name > budget.limits.name_bytes_per_value then
    return incomplete(budget, "classic_compatibility_cycle_name_shape")
  end
  return consume(budget, "name_bytes", #name, "classic_compatibility_cycle_name_bound")
end

-- Validate the raw array before traversal or copying it.  Lua's ipairs
-- semantics deliberately remain the array contract here: sparse trailing
-- keys were already outside the historical repair's traversal.
local function bounded_prerequisites(technology, budget)
  local prerequisites = technology and technology.prerequisites
  if prerequisites == nil then return prerequisites, 0, true end
  if type(prerequisites) ~= "table" then
    return nil, 0, incomplete(budget, "classic_compatibility_cycle_prerequisite_shape")
  end
  local count = #prerequisites
  if count > budget.limits.prerequisites_per_technology then
    return nil, 0, incomplete(budget, "classic_compatibility_cycle_prerequisite_shape")
  end
  if not consume(budget, "array_entries", count, "classic_compatibility_cycle_array_bound") then
    return nil, 0, false
  end
  for index = 1, count do
    if not bounded_name(prerequisites[index], budget) then return nil, 0, false end
  end
  return prerequisites, count, true
end

local function bounded_has_prerequisite(technology, prerequisite, budget)
  if not bounded_name(prerequisite, budget) then return false, false end
  local prerequisites, count, complete = bounded_prerequisites(technology, budget)
  if not complete then return false, false end
  for index = 1, count do
    if prerequisites[index] == prerequisite then return true, true end
  end
  return false, true
end

local function bounded_reaches(technologies, start_name, target_name, budget)
  if type(technologies) ~= "table" then
    return false, incomplete(budget, "classic_compatibility_cycle_technology_shape")
  end
  if not bounded_name(start_name, budget) or not bounded_name(target_name, budget) then return false, false end

  local pending, visited = {start_name}, {}
  while #pending > 0 do
    local name = table.remove(pending)
    if name == target_name then return true, true end
    if not visited[name] then
      if not consume(budget, "visits", 1, "classic_compatibility_cycle_visit_bound") then return false, false end
      visited[name] = true
      local raw_prerequisites, count, complete = bounded_prerequisites(technologies[name], budget)
      if not complete then return false, false end
      local prerequisites = {}
      for index = 1, count do prerequisites[index] = raw_prerequisites[index] end
      table.sort(prerequisites, function(a, b) return a > b end)
      for index = 1, count do
        if not consume(budget, "edges", 1, "classic_compatibility_cycle_edge_bound") then return false, false end
        pending[#pending + 1] = prerequisites[index]
      end
    end
  end
  return false, true
end

local function classic_status(budget)
  return {
    status = budget.reason and "not-evaluated" or "complete",
    reason = budget.reason,
    visits = budget.visits,
    edges = budget.edges,
    name_bytes = budget.name_bytes,
    array_entries = budget.array_entries
  }
end

local function bounded_plan(technologies, active_mods, budget)
  if type(technologies) ~= "table" then
    incomplete(budget, "classic_compatibility_cycle_technology_shape")
    return {}, classic_status(budget)
  end

  local operations = {}
  for _, repair in ipairs(REPAIRS) do
    local technology = technologies[repair.technology]
    if all_mods_active(active_mods or {}, repair.required_mods) then
      local has_edge, edge_complete = bounded_has_prerequisite(technology, repair.remove_prerequisite, budget)
      if not edge_complete then return {}, classic_status(budget) end
      if has_edge then
        local reaches, reaches_complete = bounded_reaches(technologies, repair.reverse_path_start, repair.technology, budget)
        if not reaches_complete then return {}, classic_status(budget) end
        if reaches then
          operations[#operations + 1] = {
            id = repair.id,
            technology = repair.technology,
            remove_prerequisite = repair.remove_prerequisite,
            evidence = table.concat(repair.required_mods, "+") .. ":mutual-prerequisite-path"
          }
        end
      end
    end
  end
  return operations, classic_status(budget)
end

-- A bounded application preflights every declared operation before it copies
-- any prerequisite list.  An incomplete observation therefore leaves the
-- external graph untouched; it never turns "not evaluated" into removal.
local function bounded_apply_plan(operations, technologies, budget)
  if type(operations) ~= "table" or #operations > #REPAIRS or type(technologies) ~= "table" then
    incomplete(budget, "classic_compatibility_cycle_operation_shape")
    return {}, classic_status(budget)
  end

  local prepared = {}
  for _, operation in ipairs(operations) do
    local repair = declared_repair_for_operation(operation)
    if not repair then
      incomplete(budget, "classic_compatibility_cycle_operation_shape")
      return {}, classic_status(budget)
    end
    local technology = technologies[repair.technology]
    local found, complete = bounded_has_prerequisite(technology, repair.remove_prerequisite, budget)
    if not complete then return {}, classic_status(budget) end
    if found then
      local prerequisites, count, valid = bounded_prerequisites(technology, budget)
      if not valid then return {}, classic_status(budget) end
      prepared[#prepared + 1] = {operation = operation, technology = technology, prerequisites = prerequisites, count = count}
    end
  end

  local applied = {}
  for _, entry in ipairs(prepared) do
    local prerequisites = {}
    for index = 1, entry.count do
      local prerequisite = entry.prerequisites[index]
      if prerequisite ~= entry.operation.remove_prerequisite then prerequisites[#prerequisites + 1] = prerequisite end
    end
    entry.technology.prerequisites = #prerequisites > 0 and prerequisites or nil
    applied[#applied + 1] = entry.operation
  end
  return applied, classic_status(budget)
end

function M.plan(technologies, active_mods, options)
  if not (type(options) == "table" and options.bounded == true) then
    return legacy_plan(technologies, active_mods)
  end
  return bounded_plan(technologies, active_mods, options.budget or new_classic_budget())
end

function M.apply_plan(operations, technologies, options)
  if not (type(options) == "table" and options.bounded == true) then
    for _, operation in ipairs(operations or {}) do
      local repair = declared_repair_for_operation(operation)
      local technology = repair and technologies[operation.technology] or nil
      if technology and has_prerequisite(technology, operation.remove_prerequisite) then
        local prerequisites = {}
        for _, prerequisite in ipairs(technology.prerequisites or {}) do
          if prerequisite ~= operation.remove_prerequisite then table.insert(prerequisites, prerequisite) end
        end
        technology.prerequisites = #prerequisites > 0 and prerequisites or nil
      end
    end
    return
  end
  return bounded_apply_plan(operations, technologies, options.budget or new_classic_budget())
end

local function report_repaired(operation)
  if log then
    log("[more-infinite-research] Repaired external technology prerequisite cycle " .. operation.id
      .. " by removing " .. operation.technology .. " -> " .. operation.remove_prerequisite .. ".")
  end
  D.compatibility_plan({
    key = operation.id,
    status = "repaired",
    reason = "external_technology_prerequisite_cycle",
    technology = operation.technology,
    prerequisites = operation.remove_prerequisite,
    evidence = operation.evidence
  })
end

local function report_not_evaluated(status)
  if log then
    log("[more-infinite-research] Classic compatibility cycle repair not evaluated: "
      .. tostring(status.reason) .. " visits=" .. tostring(status.visits)
      .. " edges=" .. tostring(status.edges) .. ".")
  end
  D.compatibility_plan({
    key = "muluna-astroponics-space-science-cycle",
    status = "not-evaluated",
    reason = status.reason,
    visits = status.visits,
    edges = status.edges,
    name_bytes = status.name_bytes,
    array_entries = status.array_entries
  })
end

function M.apply(options)
  local technologies = data_raw.prototypes("technology")
  if not (type(options) == "table" and options.bounded == true) then
    local operations = M.plan(technologies, mods or {})
    M.apply_plan(operations, technologies)
    for _, operation in ipairs(operations) do report_repaired(operation) end
    return operations
  end

  local budget = new_classic_budget()
  local bounded_options = {bounded = true, budget = budget}
  local operations, status = M.plan(technologies, mods or {}, bounded_options)
  if status.status ~= "complete" then
    report_not_evaluated(status)
    return {operations = {}, status = status}
  end
  local applied, apply_status = M.apply_plan(operations, technologies, bounded_options)
  if apply_status.status ~= "complete" then
    report_not_evaluated(apply_status)
    return {operations = {}, status = apply_status}
  end
  for _, operation in ipairs(applied) do report_repaired(operation) end
  return {operations = applied, status = apply_status}
end

return M

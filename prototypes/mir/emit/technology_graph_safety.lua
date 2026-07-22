local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local science = require("prototypes.mir.capabilities.science_integration.science_packs")
local fingerprint = require("prototypes.mir.core.fingerprint")
local telemetry = require("prototypes.mir.report.compiler_telemetry")

local M = {}

local function ingredient_name(ingredient)
  if type(ingredient) == "string" then return ingredient end
  return ingredient and (ingredient.name or ingredient[1]) or nil
end

local function sorted_prerequisites(technology)
  local prerequisites = {}
  for _, prerequisite in ipairs((technology and technology.prerequisites) or {}) do
    table.insert(prerequisites, prerequisite)
  end
  table.sort(prerequisites)
  return prerequisites
end

local function cycle_from_path(path, start_index, repeated_name)
  local cycle = {}
  for index = start_index, #path do table.insert(cycle, path[index]) end
  table.insert(cycle, repeated_name)
  return cycle
end

local function canonical_cycle_key(cycle)
  local count = #cycle - 1
  if count <= 0 then return table.concat(cycle, " -> ") end
  local best
  for offset = 1, count do
    local rotated = {}
    for step = 0, count - 1 do
      table.insert(rotated, cycle[((offset + step - 1) % count) + 1])
    end
    table.insert(rotated, rotated[1])
    local candidate = table.concat(rotated, " -> ")
    if not best or candidate < best then best = candidate end
  end
  return best
end

local function generated_names_in_cycle(cycle, is_generated)
  local generated, seen = {}, {}
  for index = 1, #cycle - 1 do
    local name = cycle[index]
    if is_generated(name) and not seen[name] then
      seen[name] = true
      table.insert(generated, name)
    end
  end
  table.sort(generated)
  return generated
end

local function inspect_root(root_name, state)
  if state.complete[root_name] then return end

  local path, visiting = {}, {}
  local stack = {{name = root_name, entered = false}}
  while #stack > 0 do
    local frame = stack[#stack]
    if state.complete[frame.name] then
      table.remove(stack)
    elseif not frame.entered then
      local technology = state.technology_lookup(frame.name)
      if not technology then
        error("MIR generated technology graph references missing technology " .. tostring(frame.name) .. ".", 3)
      end
      if technology.enabled == false then
        local chain = {}
        for _, entry in ipairs(path) do table.insert(chain, entry) end
        table.insert(chain, frame.name)
        error("MIR generated technology graph references disabled technology " .. frame.name
          .. " in path " .. table.concat(chain, " -> ") .. ".", 3)
      end

      frame.entered = true
      frame.prerequisites = sorted_prerequisites(technology)
      frame.next_prerequisite = 1
      table.insert(path, frame.name)
      visiting[frame.name] = #path
    elseif frame.next_prerequisite <= #frame.prerequisites then
      local prerequisite = frame.prerequisites[frame.next_prerequisite]
      frame.next_prerequisite = frame.next_prerequisite + 1
      local cycle_start = visiting[prerequisite]
      if cycle_start then
        local cycle = cycle_from_path(path, cycle_start, prerequisite)
        local generated = generated_names_in_cycle(cycle, state.is_generated)
        if #generated > 0 then
          error("MIR generated technology prerequisite cycle: " .. table.concat(cycle, " -> ") .. ".", 3)
        end
        error("External technology prerequisite cycle reachable from MIR generated technology " .. root_name
          .. ": " .. canonical_cycle_key(cycle) .. ". Factorio will reject this technology graph.", 3)
      elseif not state.complete[prerequisite] then
        table.insert(stack, {name = prerequisite, entered = false})
      end
    else
      visiting[frame.name] = nil
      table.remove(path)
      state.complete[frame.name] = true
      table.remove(stack)
    end
  end
end

local function new_inspection_state(options)
  options = options or {}
  return {
    technology_lookup = options.technology_lookup or data_raw.technology,
    is_generated = options.is_generated or generated_registry.contains,
    complete = {}
  }
end

function M.inspect_reachable(root_name, options)
  local state = new_inspection_state(options)
  inspect_root(root_name, state)
  local checked = 0
  for _ in pairs(state.complete) do checked = checked + 1 end
  return {
    valid = true,
    root = root_name,
    checked_node_count = checked
  }
end

local function assert_science_reachable(name, technology)
  local ingredients = ((technology or {}).unit or {}).ingredients or {}
  if #ingredients == 0 then
    error("MIR generated technology " .. name .. " has no research ingredients.", 3)
  end
  if not science.valid_research_ingredients(ingredients) then
    error("MIR generated technology " .. name .. " has no active lab accepting its complete science set.", 3)
  end

  for _, ingredient in ipairs(ingredients) do
    local pack_name = ingredient_name(ingredient)
    local status = science.pack_production_status(pack_name)
    if status == "unreachable" then
      error("MIR generated technology " .. name .. " uses unreachable science pack " .. tostring(pack_name) .. ".", 3)
    end
  end
end

local function planned_technologies(plan)
  local out = {}
  for _, operation in ipairs((plan and plan.operations) or {}) do
    if operation.operation == "emit_stream" or operation.operation == "emit_base_extension" then
      out[operation.technology_name] = operation
    end
  end
  return out
end

function M.assert_registered_technologies(plan)
  local state = new_inspection_state()
  local registered = generated_registry.sorted_names()
  local planned = planned_technologies(plan)
  local parity = {}
  for _, name in ipairs(registered) do
    local technology = data_raw.technology(name)
    if not technology then
      error("MIR registered generated technology is missing: " .. name .. ".", 2)
    end
    if technology.enabled == false then
      error("MIR generated technology is disabled: " .. name .. ".", 2)
    end

    inspect_root(name, state)
    assert_science_reachable(name, technology)
    if plan then
      local operation = planned[name]
      if not operation then error("MIR emitted technology is absent from CompilationPlan: " .. name .. ".", 2) end
      local expected = sorted_prerequisites(operation.technology)
      local actual = sorted_prerequisites(technology)
      if fingerprint.of(expected) ~= fingerprint.of(actual) then
        error("MIR emitted technology prerequisites differ from CompilationPlan: " .. name .. ".", 2)
      end
      local proof = plan.validation_summary and plan.validation_summary.technology_graph
        and plan.validation_summary.technology_graph.proofs[name]
      if not proof or proof.status ~= "passed" then
        error("MIR emitted technology lacks an accepted planner graph proof: " .. name .. ".", 2)
      end
      table.insert(parity, {
        technology_name = name,
        prerequisites = actual,
        prerequisite_fingerprint = fingerprint.of(actual),
        enabled = technology.enabled ~= false,
        science_lab_status = "reachable",
        scc_class = "acyclic",
        planner_proof = "passed"
      })
    end
  end
  if plan then
    local registered_set = {}
    for _, name in ipairs(registered) do registered_set[name] = true end
    for name in pairs(planned) do
      if not registered_set[name] then error("CompilationPlan accepted technology was not emitted: " .. name .. ".", 2) end
    end
  end
  local checked = 0
  for _ in pairs(state.complete) do checked = checked + 1 end
  local result = {
    schema = 1,
    valid = true,
    registered_technology_count = #registered,
    planned_technology_count = (function() local count = 0; for _ in pairs(planned) do count = count + 1 end; return count end)(),
    checked_node_count = checked,
    technologies = parity
  }
  result.parity_fingerprint = fingerprint.of(result)
  telemetry.count("technology_graph_parity_rows", #parity)
  return result
end

return M

local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local generated_registry = require("prototypes.mir.emit.effect_safety")

local M = {}

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

local function inspect_root(root_name, complete)
  if complete[root_name] then return end

  local path, visiting = {}, {}
  local stack = {{name = root_name, entered = false}}
  while #stack > 0 do
    local frame = stack[#stack]
    if complete[frame.name] then
      table.remove(stack)
    elseif not frame.entered then
      local technology = data_raw.technology(frame.name)
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
        error("MIR generated technology prerequisite cycle: " .. table.concat(cycle, " -> ") .. ".", 3)
      elseif not complete[prerequisite] then
        table.insert(stack, {name = prerequisite, entered = false})
      end
    else
      visiting[frame.name] = nil
      table.remove(path)
      complete[frame.name] = true
      table.remove(stack)
    end
  end
end

function M.assert_registered_technologies()
  local complete = {}
  for _, name in ipairs(generated_registry.sorted_generated_technology_names()) do
    local technology = data_raw.technology(name)
    if not technology then
      error("MIR registered generated technology is missing: " .. name .. ".", 2)
    end
    if technology.enabled == false then
      error("MIR generated technology is disabled: " .. name .. ".", 2)
    end
    inspect_root(name, complete)
  end
end

return M

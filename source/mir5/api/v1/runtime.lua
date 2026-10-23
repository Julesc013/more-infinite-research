-- Draft MIR API v1 runtime query surface. Registration belongs to control.lua.
local target = require("platform.target")

local M = {}

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function positive_integer(value)
  return finite(value) and value > 0 and value == math.floor(value)
end

local function available_forces()
  local current_game = rawget(_G, "game")
  if current_game == nil then return nil end
  local ok, forces = pcall(function() return current_game.forces end)
  if not ok or forces == nil then return nil end
  return forces
end

function M.get_version()
  return {major = 1, minor = 0, product = target.distribution_version}
end

function M.get_capabilities()
  return {research_query = target.research_levels == true and available_forces() ~= nil}
end

function M.get_research(force_index, technology_name)
  if not positive_integer(force_index) or force_index > 4294967295 then
    return nil, "invalid_force"
  end
  if type(technology_name) ~= "string" or technology_name == "" then
    return nil, "invalid_technology"
  end
  if target.research_levels ~= true then return nil, "unsupported_capability" end

  local forces = available_forces()
  if forces == nil then return nil, "game_unavailable" end
  -- LuaCustomTable can reject an unused numeric index even when it fits the
  -- documented uint32 key type. An absent force is an API result, not a native
  -- indexing exception propagated into another mod's event handler.
  local ok, force = pcall(function() return forces[force_index] end)
  if not ok then return nil, "force_not_found" end
  if force == nil then return nil, "force_not_found" end
  local force_ok, force_valid = pcall(function() return force.valid end)
  if not force_ok or force_valid == false then return nil, "force_not_found" end
  local technologies
  ok, technologies = pcall(function() return force.technologies end)
  if not ok or technologies == nil then return nil, "unsupported_capability" end
  local technology
  ok, technology = pcall(function() return technologies[technology_name] end)
  if not ok then return nil, "unsupported_capability" end
  if technology == nil then return nil, "technology_not_found" end

  local level
  ok, level = pcall(function() return technology.level end)
  if not ok then return nil, "unsupported_capability" end
  local prototype
  ok, prototype = pcall(function() return technology.prototype end)
  if not ok or prototype == nil then return nil, "unsupported_capability" end
  local maximum
  ok, maximum = pcall(function() return prototype.max_level end)
  if not ok then return nil, "unsupported_capability" end
  if not positive_integer(level) or (maximum ~= "infinite" and not finite(maximum)) then
    return nil, "unsupported_capability"
  end

  local researched
  ok, researched = pcall(function() return technology.researched end)
  if not ok or type(researched) ~= "boolean" then return nil, "unsupported_capability" end
  local enabled
  ok, enabled = pcall(function() return technology.enabled end)
  if not ok or type(enabled) ~= "boolean" then return nil, "unsupported_capability" end

  local status = {
    name = technology_name,
    force_index = force_index,
    researched = researched,
    level = level,
    enabled = enabled,
    max_level = maximum
  }
  local saved_ok, saved_progress = pcall(function() return technology.saved_progress end)
  if saved_ok and saved_progress ~= nil then
    if not finite(saved_progress) then return nil, "unsupported_capability" end
    status.saved_progress = saved_progress
  end
  return status
end

return M

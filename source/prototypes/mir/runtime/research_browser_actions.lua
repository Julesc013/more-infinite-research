-- Keep browser queue actions on the force's native research queue.
local M = {}

local function available(technology)
  if not technology.enabled or technology.researched or technology.prototype.hidden
      or technology.prototype.research_trigger then return false end
  for _, prerequisite in pairs(technology.prerequisites) do
    if not prerequisite.researched then return false end
  end
  return true
end

function M.can_enqueue(player, technology, action)
  if not (player and player.valid and technology and technology.valid) then return false end
  if technology.force.index ~= player.force.index or not player.force.research_enabled then return false end
  if player.permission_group and not player.permission_group.allows_action(action) then return false end
  if not available(technology) then return false end
  for _, queued in ipairs(player.force.research_queue or {}) do
    if queued.name == technology.name then return false end
  end
  return true
end

local function same_force(player, technology)
  return technology and technology.valid and technology.force.index == player.force.index
end

local function depends_on(technology, other)
  for _, prerequisite in pairs(technology.prerequisites or {}) do
    if not prerequisite.researched and prerequisite.name == other.name then return true end
  end
  return false
end

function M.can_move(player, entries, index, direction, action)
  if not (player and player.valid and player.force and player.force.valid
      and player.force.research_enabled and type(entries) == "table"
      and type(index) == "number" and index == math.floor(index)
      and type(action) == "number"
      and (direction == -1 or direction == 1)) then return false end
  local adjacent = index + direction
  -- Keep the active technology in place so reordering cannot discard its
  -- progress. The native setter receives a complete queue on a real click.
  if index <= 1 or adjacent <= 1 or adjacent > #entries then return false end
  if player.permission_group and not player.permission_group.allows_action(action) then return false end
  local technology, neighbor = entries[index], entries[adjacent]
  if not (same_force(player, technology) and same_force(player, neighbor)) then return false end
  if technology.name == neighbor.name then return false end
  if direction == -1 and depends_on(technology, neighbor) then return false end
  if direction == 1 and depends_on(neighbor, technology) then return false end
  return true
end

local function valid_order(player, entries)
  local prior = {}
  for _, technology in ipairs(entries) do
    if not same_force(player, technology) or not technology.enabled or technology.researched then return false end
    for _, prerequisite in pairs(technology.prerequisites or {}) do
      if not prerequisite.researched and not prior[prerequisite.name] then return false end
    end
    prior[technology.name] = true
  end
  return true
end

function M.move(player, index, direction, expected_name, expected_adjacent_name, action)
  if not (player and player.valid and player.force and player.force.valid) then return false end
  local force = player.force
  local entries = force.research_queue or {}
  local adjacent = type(index) == "number" and type(direction) == "number" and index + direction or nil
  if not M.can_move(player, entries, index, direction, action)
      or type(expected_name) ~= "string" or type(expected_adjacent_name) ~= "string"
      or entries[index].name ~= expected_name or entries[adjacent].name ~= expected_adjacent_name then return false end
  local proposed = {}
  for position, technology in ipairs(entries) do proposed[position] = technology end
  proposed[index], proposed[adjacent] = proposed[adjacent], proposed[index]
  if not valid_order(player, proposed) then return false end
  local active = force.current_research
  local active_name = active and active.name
  local progress = force.research_progress
  local ok = pcall(function() force.research_queue = proposed end)
  if not ok then return false end
  local actual = force.research_queue or {}
  local unchanged_head = force.current_research and force.current_research.name == active_name
  local exact = #actual == #proposed and unchanged_head
  if exact then
    for position, technology in ipairs(actual) do
      if technology.name ~= proposed[position].name then exact = false; break end
    end
  end
  if not exact then
    -- The engine can silently omit research it finds invalid. Restore the
    -- original queue if that happens instead of accepting a partial reorder.
    pcall(function() force.research_queue = entries end)
  end
  if force.current_research and force.current_research.name == active_name
      and type(progress) == "number" and force.research_progress ~= progress then
    force.research_progress = progress
  end
  return exact
end

return M

-- On-demand, read-only science flow snapshots for the selected technology.
-- This module has no storage, event subscription, cache, or steady-state work.
local M = {ingredient_limit = 16, name_limit = 1024}

local function finite_nonnegative(value)
  return type(value) == "number" and value == value and value >= 0
    and value < math.huge
end

local function valid_object(value)
  if value == nil then return false end
  local ok, result = pcall(function() return value.valid end)
  return ok and result == true
end

function M.snapshot(player, technology)
  local ok, result = pcall(function()
    local force = player and player.force
    local surface = player and player.surface
    if not valid_object(force) or not valid_object(surface) or not valid_object(technology) then return nil end
    local technology_force = technology.force
    if not valid_object(technology_force) or technology_force.index ~= force.index then return nil end
    local precision = defines and defines.flow_precision_index and defines.flow_precision_index.one_minute
    if type(precision) ~= "number" then return nil end

    local ingredients = technology.research_unit_ingredients
    if type(ingredients) ~= "table" or #ingredients == 0 or #ingredients > M.ingredient_limit then return nil end
    local modern_api = type(force.get_item_production_statistics) == "function"
    local statistics = modern_api and force.get_item_production_statistics(surface)
      or (not modern_api and force.item_production_statistics or nil)
    if not valid_object(statistics) or type(statistics.get_flow_count) ~= "function" then return nil end

    local rows, seen = {}, {}
    for _, ingredient in ipairs(ingredients) do
      local name = ingredient and ingredient.name
      if type(name) ~= "string" or name == "" or #name > M.name_limit or seen[name] then return nil end
      seen[name] = true
      local produced, consumed
      if modern_api then
        produced = statistics.get_flow_count{
          name = {name = name, quality = "normal"}, category = "input", precision_index = precision, count = false
        }
        consumed = statistics.get_flow_count{
          name = {name = name, quality = "normal"}, category = "output", precision_index = precision, count = false
        }
      else
        produced = statistics.get_flow_count{name = name, input = true, precision_index = precision, count = false}
        consumed = statistics.get_flow_count{name = name, input = false, precision_index = precision, count = false}
      end
      if not finite_nonnegative(produced) or not finite_nonnegative(consumed) then return nil end
      rows[#rows + 1] = {name = name, produced = produced, consumed = consumed, balance = produced - consumed}
    end
    local tick = game and game.tick
    if not finite_nonnegative(tick) or tick ~= math.floor(tick) then return nil end
    return {
      technology_id = technology.name,
      force_name = force.name,
      scope = modern_api and "surface" or "force",
      surface_name = modern_api and surface.name or nil,
      tick = tick,
      rows = rows,
    }
  end)
  return ok and result or nil
end

return M

-- Runtime-only Library services. Resolve engine objects inside callbacks,
-- never while control.lua is being loaded or from persisted state.
local M = {production_scope = "surface", recipe_browser_available = true}

function M.open_recipe(player, name)
  local recipe = prototypes.recipe[name]
  if not recipe then return false end
  player.open_factoriopedia_gui(recipe)
  return true
end

function M.is_trigger_research(prototype)
  return prototype.research_trigger ~= nil
end

function M.production_statistics(force, surface)
  return force.get_item_production_statistics(surface)
end

function M.item_flow_count(statistics, name, produced, precision)
  return statistics.get_flow_count{
    name = {name = name, quality = "normal"},
    category = produced and "input" or "output", precision_index = precision, count = false
  }
end

function M.prototype_collections()
  return prototypes
end

function M.write_file(path, contents, append, player_index)
  return helpers.write_file(path, contents, append, player_index)
end

return M

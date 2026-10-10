-- Factorio 1.0/1.1 expose runtime prototypes and file output through game.
-- This adapter is selected by composition; it never probes absent 2.x APIs.
-- Loading it is safe before game exists. Callers resolve objects in callbacks.
local M = {production_scope = "force"}

function M.is_trigger_research(prototype)
  -- This engine has no trigger research or research_trigger prototype field.
  return false
end

function M.production_statistics(force, surface)
  -- The older API aggregates the entire force, not the selected surface.
  return force.item_production_statistics
end

function M.item_flow_count(statistics, name, produced, precision)
  return statistics.get_flow_count{
    name = name, input = produced, precision_index = precision, count = false
  }
end

function M.prototype_collections()
  return {
    item = game.item_prototypes,
    fluid = game.fluid_prototypes,
    recipe = game.recipe_prototypes,
    technology = game.technology_prototypes,
    mod_setting = game.mod_setting_prototypes
  }
end

function M.write_file(path, contents, append, player_index)
  return game.write_file(path, contents, append, player_index)
end

return M

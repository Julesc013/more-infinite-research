-- Factorio 1.0/1.1 expose runtime prototypes and file output through game.
-- This adapter is selected by composition; it never probes absent 2.x APIs.
-- Loading it is safe before game exists. Callers resolve objects in callbacks.
local M = {}

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

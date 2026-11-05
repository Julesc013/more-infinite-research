-- One historically authored RIC route. Metadata is safe in settings/control;
-- prototype inspection and construction stay in this integration's research module.
local M = {
  mod = "real-industrial-chemistry",
  family = "research_material_ric_coke",
  id = "recipe-prod-research_material_ric_coke-1",
  recipe = "ric-carbonise-marine-biomass",
  owner = "ric-coking",
  order = "p[research_material_ric_coke]",
}

function M.applies(active_mods, target)
  return type(target) == "table" and target.id == "f210"
    and type(active_mods) == "table" and type(active_mods[M.mod]) == "string"
    and active_mods[M.mod] ~= ""
end

function M.is_marine(startup)
  local setting = type(startup) == "table" and startup["ric-world-mode"]
  return type(setting) == "table" and setting.value == "marine"
end

return M

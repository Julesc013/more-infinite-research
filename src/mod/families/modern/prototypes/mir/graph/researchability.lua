local M = {}

function M.evaluate(node, services)
  if not node.enabled then return "prerequisite_disabled" end
  if node.research_trigger then return nil end
  if #node.science_packs == 0 or not node.has_research_count then return "research_mechanism_missing" end
  if services and services.valid_research_ingredients
    and not services.valid_research_ingredients(node.science_packs) then
    return "research_lab_unavailable"
  end
  if services and services.pack_production_status then
    for _, pack in ipairs(node.science_packs) do
      if services.pack_production_status(pack) == "unreachable" then return "research_science_unreachable" end
    end
  end
  return nil
end

return M

local function fail(message) error("MIR automatic productivity preview validation failed: " .. message) end
local artifact_prototype = (data.raw["mod-data"] or {})["more-infinite-research-generation-plan"]
local artifact = artifact_prototype and artifact_prototype.data
local catalog_prototype = (data.raw["mod-data"] or {})["more-infinite-research-technology-catalog"]
local catalog = catalog_prototype and catalog_prototype.data
if not artifact or artifact.kind ~= "mir-generation-plan-public" then
  fail("published generation-plan artifact is missing")
end
if not catalog or not catalog.provider_summary or catalog.provider_summary.decision_count < 1 then
  fail("preview action recorded no published family decisions")
end
for _, row in ipairs(artifact.rows or {}) do
  if (row.stream_id == "research_auto_assembling_machine" or row.stream_id == "research_auto_lab")
    and row.reason ~= "automatic_productivity_preview_only" then
    fail("automatic family row has wrong preview-action reason " .. tostring(row.reason))
  end
end
for _, technology in pairs(data.raw.technology or {}) do
  if technology.max_level == "infinite" then
    for _, effect in ipairs(technology.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == "assemble-alpha" then
        fail("preview action attached an automatic recipe")
      end
    end
  end
end

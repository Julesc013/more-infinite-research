local data_raw = require("prototypes.mir.platform.factorio.data_raw")

local M = {}

function M.emit_productivity_family_adoption(payload)
  if not payload then return end

  data_raw.extend({
    {
      type = "mod-data",
      name = payload.name,
      data_type = payload.data_type,
      data = payload.data
    }
  })
end

function M.emit_coverage(artifact)
  if not artifact then return end
  data_raw.extend({
    {
      type = "mod-data",
      name = "more-infinite-research-coverage-report",
      data_type = "more-infinite-research.coverage-report",
      data = artifact
    }
  })
end

function M.emit_generation_plan(artifact)
  if not artifact then return end
  data_raw.extend({
    {
      type = "mod-data",
      name = "more-infinite-research-generation-plan",
      data_type = "more-infinite-research.generation-plan",
      data = artifact
    }
  })
end

return M

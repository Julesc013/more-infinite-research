local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local target_line = require("prototypes.mir.platform.factorio.target_line")

local M = {}

local function emit(prototype)
  if not target_line.mod_data_supported() then return false end
  data_raw.extend({prototype})
  return true
end

function M.emit_productivity_family_adoption(payload)
  if not payload then return end

  return emit({
    type = "mod-data",
    name = payload.name,
    data_type = payload.data_type,
    data = payload.data
  })
end

function M.emit_coverage(artifact)
  if not artifact then return end
  return emit({
    type = "mod-data",
    name = "more-infinite-research-coverage-report",
    data_type = "more-infinite-research.coverage-report",
    data = artifact
  })
end

function M.emit_generation_plan(artifact)
  if not artifact then return end
  return emit({
    type = "mod-data",
    name = "more-infinite-research-generation-plan",
    data_type = "more-infinite-research.generation-plan",
    data = artifact
  })
end

function M.emit_compiler_evidence(artifact)
  if not artifact then return end
  return emit({
    type = "mod-data",
    name = "more-infinite-research-compiler-evidence",
    data_type = "more-infinite-research.compiler-evidence",
    data = artifact
  })
end

return M

local D = require("prototypes.mir.report.diagnostics_sink")
local native_modifiers = require("prototypes.mir.planner.native_modifiers")
local technology_operation_executor = require("prototypes.mir.emit.technology_operation_executor")

local M = {}

local function assert_artifact(artifact)
  if type(artifact) ~= "table" or artifact.schema ~= 3 or type(artifact.rows) ~= "table" then
    error("Stream executor requires a finalized GenerationPlan artifact.", 3)
  end
end

function M.apply(artifact, journal, transformations_by_stream)
  assert_artifact(artifact)
  for _, row in ipairs(artifact.rows) do
    for _, conflict in ipairs((row.effect_ownership and row.effect_ownership.lost) or {}) do
      D.recipe_owner({
        recipe = conflict.recipe,
        action = "planned-owner-won",
        owners = conflict.winner_owner,
        owner_actions = conflict.winner_stream,
        warning_class = conflict.reason
      })
    end
    if row.action == "emit" then
      if row.direct_effects then
        native_modifiers.record_overlaps(row.stream_key, row.overlap_effects)
      end
      if not row.technology_design then
        error("Stream executor requires TechnologyDesign schema 2 for " .. tostring(row.stream_key) .. ".", 2)
      end
      local technology = technology_operation_executor.apply_stream_row(
        row, journal, transformations_by_stream and transformations_by_stream[row.stream_key])
      if D.enabled() and not row.direct_effects then
        log("[more-infinite-research] Registered technology " .. technology.name)
      end
    elseif row.action == "adopt" then
      technology_operation_executor.apply_stream_row(
        row, journal, transformations_by_stream and transformations_by_stream[row.stream_key])
    elseif row.reason ~= "disabled" then
      log("[more-infinite-research] Skipping stream " .. row.stream_key .. " because " .. row.reason .. ".")
    end
    D.stream(row.diagnostics)
  end
end

return M

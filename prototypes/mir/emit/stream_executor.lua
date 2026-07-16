local D = require("prototypes.mir.report.diagnostics_sink")
local adoption_transaction = require("prototypes.mir.emit.transactions.productivity_family_adoption")
local native_modifiers = require("prototypes.mir.planner.native_modifiers")
local stream_emitter = require("prototypes.mir.emit.stream_spec_adapter")

local M = {}

local function assert_artifact(artifact)
  if type(artifact) ~= "table" or artifact.schema ~= 3 or type(artifact.rows) ~= "table" then
    error("Stream executor requires a finalized GenerationPlan artifact.", 3)
  end
end

function M.apply(artifact)
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
      local technology = stream_emitter.emit(row.stream_key, row.spec, row.fields)
      if D.enabled() and not row.direct_effects then
        log("[more-infinite-research] Registered technology " .. technology.name)
      end
    elseif row.action == "adopt" then
      adoption_transaction.apply(row.adoption)
    elseif row.reason ~= "disabled" then
      log("[more-infinite-research] Skipping stream " .. row.stream_key .. " because " .. row.reason .. ".")
    end
    D.stream(row.diagnostics)
  end
end

return M

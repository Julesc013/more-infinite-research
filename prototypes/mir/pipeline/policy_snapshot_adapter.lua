local effective_settings = require("prototypes.mir.settings.effective")
local compatibility_policy = require("prototypes.mir.compatibility.policy_authority")
local streams = require("prototypes.mir.streams.registry")
local promotion_registry = require("prototypes.mir.domain.technology.promotion_registry")
local hard_gate_authority = require("prototypes.mir.domain.technology.hard_gate_authority")
local effect_contracts = require("prototypes.mir.integrity.effect_contracts")
local quality_profiles = require("prototypes.mir.domain.technology.generated_quality_profiles")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local contract = require("prototypes.mir.domain.compiler.policy_snapshot")

local M = {}

function M.capture(context)
  local settings_snapshot = effective_settings.snapshot(context)
  return contract.new({
    effective_settings = settings_snapshot,
    compatibility_policy = compatibility_policy.snapshot(),
    stream_policy = streams.snapshot(),
    promotion_authority = promotion_registry.snapshot(),
    hard_gate_authority = hard_gate_authority.snapshot(),
    effect_contract_authority = effect_contracts.snapshot(),
    quality_profiles = quality_profiles,
    transformation_policy = {
      schema = 1,
      technology_create_authority = "emit/technology_operation_executor.lua",
      technology_patch_authority = "emit/technology_operation_executor.lua",
      mutation_journal_required = true
    },
    execution_mode = context and context:execution_mode() or "SAFE",
    review_policy = {
      allow_unbudgeted_review = false,
      allow_release_review = false,
      fail_reviewed_mode = false
    },
    weapon_overlap_mode = effective_settings.get("mir-adjust-vanilla-weapon-speed-techs", context)
      or target_line.weapon_overlap_default()
  })
end

return M

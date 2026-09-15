local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local overlay_loader = require("prototypes.mir.compatibility.overlay_loader")
local claim_registry = require("prototypes.mir.compatibility.claim_registry")
local compatibility_packs = require("prototypes.mir.compatibility.packs.registry")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}

local function build()
  local context = compiler_context.current()
  local cached = context:state_view("compatibility_policy_authority")
  if cached then return cached end
  local policy = {
    schema = 1,
    overlays = deepcopy(overlay_loader.overlays()),
    active_packs = compatibility_packs.snapshot(),
    claims = deepcopy(claim_registry.claims),
    sources = deepcopy(claim_registry.authority)
  }
  table.sort(policy.overlays, function(left, right) return left.id < right.id end)
  table.sort(policy.claims, function(left, right) return left.id < right.id end)
  policy.policy_fingerprint = fingerprint.of({
    overlays = policy.overlays,
    active_packs = policy.active_packs,
    claims = policy.claims,
    sources = policy.sources
  })
  return context:set_state("compatibility_policy_authority", policy)
end

function M.snapshot()
  return deepcopy(build())
end

function M.active_packs()
  return deepcopy(build().active_packs)
end

function M.candidate_seeds()
  return compatibility_packs.candidate_seeds(build().active_packs)
end

function M.resolve_candidate(candidate)
  return compatibility_packs.resolve_candidate(candidate, build().active_packs)
end

function M.blocker_is_reviewable(blocker)
  return compatibility_packs.blocker_is_reviewable(blocker)
end

function M.authorizes_family_stream(stream_key, family)
  return compatibility_packs.authorizes_family_stream(stream_key, family, build().active_packs)
end

function M.science_roles_for_stream(stream_key)
  return compatibility_packs.science_roles_for_stream(stream_key, build().active_packs)
end

function M.active_known_competing_productivity_profiles()
  return compatibility_packs.active_known_competing_productivity_profiles(build().active_packs)
end

return M

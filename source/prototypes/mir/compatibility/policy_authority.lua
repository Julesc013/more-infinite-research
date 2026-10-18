local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local overlay_loader = require("prototypes.mir.compatibility.overlay_loader")
local claim_registry = require("prototypes.mir.compatibility.claim_registry")
local compatibility_packs = require("prototypes.mir.compatibility.packs.registry")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local factorio_mods = require("prototypes.mir.platform.factorio.mods")

local M = {}

-- This is a retained *selection* policy for the exact observed F200
-- Bob/Angel input.  It is deliberately not a claim that the omitted packs
-- cannot be produced: the declared binding graph continues to validate and
-- expose their positive sources.  The consumer validates those sources and a
-- real accepting lab before it applies the configured-setting selection.
local BOB_ANGEL_422_MODS = {
  base = "2.0.77",
  angelsbioprocessing = "2.0.3",
  angelspetrochem = "2.0.3",
  angelsrefining = "2.0.4",
  angelssmelting = "2.0.5",
  bobelectronics = "2.1.1",
  boblibrary = "2.1.0",
  bobores = "2.1.2",
  bobplates = "2.1.1",
  bobrevamp = "2.1.1"
}

local BOB_ANGEL_422_RETAINED_ROLES = {
  {pack = "chemical-science-pack", role = "exclude"},
  {pack = "production-science-pack", role = "exclude"},
  {pack = "utility-science-pack", role = "exclude"},
  {pack = "angels-token-bio", role = "exclude"}
}

local function matches_exact_mods(expected, active)
  for name, version in pairs(expected) do
    if active[name] ~= version then return false end
  end
  return true
end

local function retained_science_selections(active_mods)
  if not matches_exact_mods(BOB_ANGEL_422_MODS, active_mods) then return {} end
  return {{
    id = "bob-angel-422",
    required_mod_versions = deepcopy(BOB_ANGEL_422_MODS),
    roles = deepcopy(BOB_ANGEL_422_RETAINED_ROLES)
  }}
end

local function build()
  local context = compiler_context.current()
  local cached = context:state_view("compatibility_policy_authority")
  if cached then return cached end
  local policy = {
    schema = 1,
    overlays = deepcopy(overlay_loader.overlays()),
    active_packs = compatibility_packs.snapshot(),
    claims = deepcopy(claim_registry.claims),
    sources = deepcopy(claim_registry.authority),
    retained_science_selections = retained_science_selections(factorio_mods.snapshot())
  }
  table.sort(policy.overlays, function(left, right) return left.id < right.id end)
  table.sort(policy.claims, function(left, right) return left.id < right.id end)
  policy.policy_fingerprint = fingerprint.of({
    overlays = policy.overlays,
    active_packs = policy.active_packs,
    claims = policy.claims,
    sources = policy.sources,
    retained_science_selections = policy.retained_science_selections
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
  local roles = compatibility_packs.science_roles_for_stream(stream_key, build().active_packs)
  -- Space Is Fake deliberately retires space science, while retaining its
  -- item and laboratory input. Prototype membership is not playable supply.
  -- Express this through the existing science policy, before generic pack
  -- expansion and prerequisite planning, without changing upstream prototypes.
  if factorio_mods.snapshot()["space-is-fake"] then
    roles[#roles + 1] = {
      pack = "space-science-pack",
      role = "exclude",
      source = "builtin-space-is-fake-retirement",
      reason = "space-is-fake-retired-space-progression"
    }
  end
  -- Published 4.2.2 selected a smaller configured science vector for the
  -- recorded Bob/Angel input.  The source-owned policy snapshot carries the
  -- active declaration and its required behavior-mod tuple, so its role
  -- selection and fingerprint stay aligned.  The selector separately
  -- validates pack sources, direct owners and an accepting laboratory.
  for _, selection in ipairs(build().retained_science_selections or {}) do
    for _, retained_role in ipairs(selection.roles or {}) do
      roles[#roles + 1] = {
        pack = retained_role.pack,
        role = retained_role.role,
        configured_only = true,
        retained_selection = selection.id,
        source = "builtin-bob-angel-422-configured-selection",
        reason = "published-422-configured-science-vector"
      }
    end
  end
  return roles
end

function M.active_known_competing_productivity_profiles()
  return compatibility_packs.active_known_competing_productivity_profiles(build().active_packs)
end

return M

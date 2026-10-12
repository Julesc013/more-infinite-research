-- Source-bound controls for the Classic compiler scope surfaced by the
-- Research Library.  These are runtime DTO controls only: no Factorio
-- process, GUI automation, or package is created.

local assertions, failures = 0, {}

local function check(id, condition, detail)
  assertions = assertions + 1
  if condition then return end
  failures[#failures + 1] = id .. ": " .. detail
end

local PROVIDER = "prototypes.mir.runtime.research_browser_mir_provider"
local TARGET = "prototypes.mir.platform.factorio.target_line"
local HOST = "prototypes.mir.platform.factorio.browser_host"
local CONTROL = "prototypes.mir.runtime.maximum_level_control"
local CATALOG = "prototypes.mir.settings.catalog"
local STARTUP = "prototypes.mir.runtime.startup_settings"
local CODEC = "prototypes.mir.settings.profile_codec"
local COMPILER_PROFILE = "prototypes.mir.settings.compiler_profile"

local function unload(name)
  package.loaded[name] = nil
  package.preload[name] = nil
end

local function provider_for(mod_data_supported, factorio_version)
  for _, name in ipairs{PROVIDER, TARGET, HOST, CONTROL, CATALOG, STARTUP, CODEC, COMPILER_PROFILE} do unload(name) end
  local prototype_collections = {mod_data = {}, mod_setting = {}}
  package.preload[TARGET] = function()
    return {
      factorio_version = factorio_version or "2.1",
      mod_data_supported = function() return mod_data_supported end
    }
  end
  package.preload[HOST] = function()
    return {prototype_collections = function() return prototype_collections end}
  end
  package.preload[CONTROL] = function()
    return {runtime_settings_bindings = function() return {} end}
  end
  package.preload[CATALOG] = function()
    return {spec = function() return nil end, validate_value = function() return false end}
  end
  package.preload[STARTUP] = function()
    return {get = function() return nil end}
  end
  package.preload[CODEC] = function()
    return {import_setting_name = "mir-settings-profile-import", decode = function() return nil end}
  end
  return require(PROVIDER), prototype_collections
end

local fingerprint = require("prototypes.mir.core.fingerprint")
local browser_core = require("prototypes.mir.runtime.research_browser_core")
local expected_unsupported = {
  "automatic-families",
  "competing-owner-replacements",
  "generic-mod-inference",
  "material-progression",
  "recipe-productivity",
  "weapon-speed-redistribution"
}

local function sealed_profile(ids, unsupported)
  local record = {
    schema = 1,
    kind = "mir-classic-profile-public",
    profile = "classic",
    full_catalog_status = "not-evaluated",
    supported_manifest_ids = ids,
    unsupported_classes = unsupported or expected_unsupported,
    omitted_research_not_preserved = true
  }
  record.profile_fingerprint = fingerprint.of(record)
  return record
end

_G.settings = {startup = {["mir-compiler-profile"] = {value = "classic"}}}
local modern, modern_prototypes = provider_for(true)
modern_prototypes.mod_data["more-infinite-research-compiler-profile"] = {
  data = sealed_profile({"base-continuation/braking-force", "research_character_reach"})
}
local force = {valid = true, technologies = {}}
local modern_snapshot = modern.list_snapshot(force)
local scope = modern_snapshot.compiler_scope
check("CBR-01", scope and scope.state == "available" and scope.profile == "classic"
    and scope.full_catalog_status == "not-evaluated" and scope.omitted_research_not_preserved == true,
  "a sealed current classic profile must be visible even when no generation plan exists")
check("CBR-02", scope and #scope.supported_manifest_ids == 2
    and scope.supported_manifest_ids[1] == "base-continuation/braking-force"
    and scope.unsupported_classes[6] == "weapon-speed-redistribution"
    and not next(modern_snapshot.families),
  "the scope transport must retain exact sorted emitted identities without inventing a normal family")
check("CBR-03", browser_core.normalize_enrichment(modern_snapshot) ~= nil,
  "the portable browser core must retain a valid reduced-scope status")
scope.supported_manifest_ids[1] = "forged"
scope.unsupported_classes[1] = "forged"
local modern_again = modern.list_snapshot(force)
check("CBR-04", modern_again.compiler_scope.supported_manifest_ids[1] == "base-continuation/braking-force"
    and modern_again.compiler_scope.unsupported_classes[1] == "automatic-families",
  "a returned scope DTO cannot mutate the cached sealed profile")

local forged_scope = modern.list_snapshot(force)
forged_scope.compiler_scope.unsupported_classes[1] = "forged"
check("CBR-05", browser_core.normalize_enrichment(forged_scope) == nil,
  "the browser core rejects an invented unsupported-class disposition")
local malformed = modern_prototypes.mod_data["more-infinite-research-compiler-profile"].data
malformed.supported_manifest_ids[1] = "forged-after-seal"
modern.invalidate_omissions()
local unavailable = modern.list_snapshot(force).compiler_scope
check("CBR-06", unavailable and unavailable.state == "unavailable"
    and unavailable.full_catalog_status == "not-evaluated",
  "a malformed modern classic manifest must surface unavailable scope rather than empty full support")
check("CBR-07", browser_core.normalize_enrichment(modern.list_snapshot(force)) ~= nil,
  "an explicit unavailable scope remains a usable empty Library envelope")

_G.settings = {startup = {["mir-compiler-profile"] = {value = "full"}}}
modern.invalidate_omissions()
check("CBR-08", modern.list_snapshot(force).compiler_scope == nil,
  "a selected full compiler profile must not inherit a stale classic warning")

_G.settings = {startup = {["mir-compiler-profile"] = {value = "classic"}}}
local legacy, legacy_prototypes = provider_for(false)
local declarations = require("prototypes.mir.planner.classic.declarations")
local reach = declarations.direct_streams.research_character_reach
local mining = declarations.direct_streams.research_character_mining_speed
local legacy_force = {valid = true, technologies = {
  [reach.technology_name] = {valid = true},
  [mining.technology_name] = {valid = true}
}}
local legacy_scope = legacy.list_snapshot(legacy_force).compiler_scope
check("CBR-09", legacy_scope and legacy_scope.state == "available"
    and #legacy_scope.supported_manifest_ids == 2
    and legacy_scope.supported_manifest_ids[1] == "research_character_mining_speed"
    and legacy_scope.supported_manifest_ids[2] == "research_character_reach",
  "F200 scope must list only direct declared identities verified in the live force")
check("CBR-10", legacy_scope and legacy_scope.full_catalog_status == "not-evaluated"
    and legacy_scope.omitted_research_not_preserved == true,
  "F200 fallback must retain the reduced-support and save-preservation warning")
check("CBR-11", next(legacy_prototypes.mod_data) == nil,
  "the F200 fallback must not fabricate unavailable mod-data transport")

_G.settings = {startup = {["mir-compiler-profile"] = {value = "full"}}}
check("CBR-12", legacy.list_snapshot(legacy_force).compiler_scope == nil,
  "F200 full selection must not receive the classic fallback scope")

_G.settings = {startup = {["mir-compiler-profile"] = {value = "classic"}}}
local historical = provider_for(false, "0.18")
check("CBR-13", historical.list_snapshot(legacy_force).compiler_scope == nil,
  "A historical line selected by the canonical full profile must not show a Classic warning")

if #failures > 0 then error(table.concat(failures, "\n"), 0) end

return {assertions = assertions}

-- Source-bound route control for the explicit classic compiler profile.
--
-- This control intentionally loads the data-final-fixes stage with isolated
-- preload sentinels.  It proves the selected branch without loading the
-- opposing compiler, which is the property needed to avoid the full science
-- and material planner when the reduced profile is explicitly selected.

local assertions, failures = 0, {}

local function check(id, condition, detail)
  assertions = assertions + 1
  if condition then return end
  failures[#failures + 1] = id .. ": " .. detail
end

local PROFILE = "prototypes.mir.settings.compiler_profile"
local FINAL_STAGE = "prototypes.mir.stage.data_final_fixes"
local DATA_STAGE = "prototypes.mir.stage.data"
local CLASSIC = "prototypes.mir.pipeline.classic_compiler"
local FULL = "prototypes.mir.pipeline.commands"
local TARGET = "prototypes.mir.platform.factorio.target_line"
local FIXTURE_TARGET = _G.MIR_CLASSIC_ROUTING_TARGET or "f210"

local function unload(name)
  package.loaded[name] = nil
  package.preload[name] = nil
end

local function reset_final_stage()
  unload(FINAL_STAGE)
  unload(PROFILE)
  unload(CLASSIC)
  unload(FULL)
  unload(TARGET)
end

local function load_final_stage(profile, classic, full, factorio_version)
  reset_final_stage()
  _G.settings = {startup = profile and {["mir-compiler-profile"] = {value = profile}} or {}}
  package.preload[TARGET] = function()
    return {factorio_version = factorio_version or "2.1"}
  end
  package.preload[CLASSIC] = function()
    if not classic then error("Classic compiler was loaded in the full profile", 0) end
    return {run = classic}
  end
  package.preload[FULL] = function()
    if not full then error("Full pipeline commands were loaded in the classic profile", 0) end
    return {run_all = full}
  end
  return require(FINAL_STAGE)
end

-- Explicit Classic selection must bypass the full compiler sentinel.
local classic_calls, full_calls = 0, 0
local classic_stage = load_final_stage("classic", function()
  classic_calls = classic_calls + 1
  return {profile = "classic", result = "classic-emitted"}
end, nil)
local classic_result = classic_stage.run()
check("CPR-01", classic_calls == 1 and classic_result and classic_result.profile == "classic",
  "An explicit reduced profile setting must select and return the classic compiler")
check("CPR-02", full_calls == 0 and package.loaded[FULL] == nil,
  "Classic selection must not require full pipeline commands")
check("CPR-03", package.loaded[CLASSIC] ~= nil,
  "Classic selection must require the classic compiler only after selection")

-- An absent setting in an existing configuration must retain Full.
local full_stage = load_final_stage(nil, nil, function(options)
  full_calls = full_calls + 1
  return {profile = "full", return_snapshot = options and options.return_snapshot}
end)
local full_result = full_stage.run()
check("CPR-04", full_calls == 1 and full_result and full_result.profile == "full"
  and full_result.return_snapshot == false,
  "The default full profile must preserve the normal no-snapshot command invocation")
check("CPR-05", package.loaded[CLASSIC] == nil and package.loaded[FULL] ~= nil,
  "Full selection must not require the classic compiler")

-- The default profile applies only to modern Factorio lines.  Historical
-- numeric-unit packages retain their established full/reduced surface path
-- even when a copied modern startup setting is absent.
local historic_full_calls = 0
local historic_stage = load_final_stage(nil, nil, function(options)
  historic_full_calls = historic_full_calls + 1
  return {profile = "historical-full", return_snapshot = options and options.return_snapshot}
end, "0.18")
local historic_result = historic_stage.run()
check("CPR-06", historic_full_calls == 1 and historic_result and historic_result.profile == "historical-full"
    and package.loaded[CLASSIC] == nil,
  "A historical Factorio line must retain the full-compatible branch before compiler loading")

-- The standalone profile reader has no catalog dependency and rejects an
-- invalid direct value before either compiler can execute.
unload(PROFILE)
_G.settings = {startup = {}}
local profile = require(PROFILE)
local descriptor = profile.prototype()
check("CPR-07", profile.name == "mir-compiler-profile" and profile.get() == "full",
  "An existing startup configuration without the new setting must retain the full catalogue")
check("CPR-08", descriptor.type == "string-setting" and descriptor.setting_type == "startup"
  and descriptor.default_value == "full" and descriptor.allowed_values[1] == "classic"
  and descriptor.allowed_values[2] == "full",
  "The profile setting must default to full while exposing only classic and full startup choices")
_G.settings = {startup = {["mir-compiler-profile"] = {value = "unsafe-unknown"}}}
local invalid_ok, invalid_reason = pcall(profile.get)
check("CPR-09", invalid_ok == false and tostring(invalid_reason):find("Unsupported MIR compiler profile", 1, true) ~= nil,
  "An invalid profile must fail before it can select either compiler")

-- stage.data constructs the Library shortcut but must no longer load the
-- stream registry merely for that presentation shell.  This guard covers the
-- earlier data-stage import, not only final-fixes routing.
unload(DATA_STAGE)
unload("prototypes.mir.streams.registry")
unload("prototypes.mir.platform.factorio.target_line")
unload("prototypes.mir.platform.factorio.data_raw")
unload("prototypes.mir.platform.factorio.mods")
local extended = {}
package.preload["prototypes.mir.streams.registry"] = function()
  error("stage.data imported the full stream registry", 0)
end
package.preload["prototypes.mir.platform.factorio.target_line"] = function()
  return {feature_enabled = function(name) return name == "research_library" end}
end
package.preload["prototypes.mir.platform.factorio.data_raw"] = function()
  return {extend = function(rows) for _, row in ipairs(rows) do extended[#extended + 1] = row end end}
end
package.preload["prototypes.mir.platform.factorio.mods"] = function()
  return {exists = function() return false end}
end
local data_stage = require(DATA_STAGE)
data_stage.run()
check("CPR-10", #extended == 1 and extended[1].type == "shortcut"
  and extended[1].name == "mir-research-browser" and extended[1].icon == "__base__/graphics/icons/lab.png",
  "The classic-safe Library shortcut must still be registered without a stream catalog")
check("CPR-11", package.loaded["prototypes.mir.streams.registry"] == nil,
  "The data stage must not load the full stream registry for its shortcut")

-- Exercise the actual declared planner, common TransformationPlan compiler,
-- operation executor, and MutationJournal together.  The tiny data-stage
-- input has only direct declared science/tool/lab facts; every generic
-- compiler entry point below is an error sentinel.  This proves the normal
-- Classic route does not merely choose a stub before expanding the full
-- acquisition or stream compiler.
local forbidden_classic_modules = {
  "prototypes.mir.streams.registry",
  "prototypes.mir.pipeline.commands",
  "prototypes.mir.planner.stream_compiler.compile",
  "prototypes.mir.planner.science.pack_production_reachability",
  "prototypes.mir.planner.science.recipe_route_feasibility",
  "prototypes.mir.planner.recipe_matching",
  "prototypes.mir.planner.technology_catalog.build"
}
for _, name in ipairs(forbidden_classic_modules) do unload(name) end
unload(CLASSIC)
unload("prototypes.mir.planner.classic.plan")
unload("prototypes.mir.platform.factorio.data_raw")
unload(TARGET)
for _, name in ipairs(forbidden_classic_modules) do
  package.preload[name] = function() error("Classic compiler loaded forbidden module: " .. name, 0) end
end
local classic_science = {
  "automation-science-pack", "logistic-science-pack", "military-science-pack",
  "chemical-science-pack", "production-science-pack", "utility-science-pack"
}
local classic_tools = {}
for _, name in ipairs(classic_science) do classic_tools[name] = {name = name} end
_G.data = {raw = {
  tool = classic_tools,
  technology = {
    ["utility-science-pack"] = {name = "utility-science-pack", enabled = true, prerequisites = {}}
  },
  lab = {classic_lab = {name = "classic_lab", enabled = true, inputs = classic_science}}
}}
function data:extend(rows)
  for _, row in ipairs(rows) do
    self.raw[row.type] = self.raw[row.type] or {}
    if self.raw[row.type][row.name] then error("duplicate test prototype: " .. tostring(row.name), 0) end
    self.raw[row.type][row.name] = row
  end
end
_G.settings = {startup = {}}
_G.log = function() end
package.preload[TARGET] = function()
  return {
    factorio_version = "2.1",
    -- Exercise the independent pipeline-extent setting path with an absent
    -- MIRSET1 import.  It must read the raw default and leave the full
    -- settings catalogue/stream registry untouched.
    feature_enabled = function(name) return name == "pipeline_extent" or name == "scripted_techs" end,
    effect_supported = function() return true end,
    mod_data_supported = function() return FIXTURE_TARGET == "f210" end
  }
end
local actual_classic = require(CLASSIC)
local actual_context = actual_classic.run()
local actual_selected = actual_context:state_snapshot("classic_compilation_plan")
local actual_profile = actual_context:state_snapshot("classic_profile")
local actual_receipt = actual_context:state_snapshot("classic_mutation_journal")
local expected_direct = require("prototypes.mir.domain.compiler.classic_declarations").direct_streams
local emitted_direct = 0
for _, declaration in pairs(expected_direct) do
  local technology = data.raw.technology[declaration.technology_name]
  if technology and technology.type == "technology" and technology.max_level == "infinite" then
    emitted_direct = emitted_direct + 1
  end
end
check("CPR-12", #actual_selected.stream_plan.rows == 5 and emitted_direct == 5,
  "The actual Classic declared planner must produce and emit its finite direct core")
check("CPR-13", actual_receipt.required_operation_count == 5 and #actual_receipt.entries == 5
    and actual_receipt.complete == true,
  "The Classic route must use the common plan-bound operation executor and complete MutationJournal")
check("CPR-14", actual_profile and actual_profile.profile == "classic"
    and actual_profile.full_catalog_status == "not-evaluated"
    and #actual_profile.supported_manifest_ids == 5
    and actual_profile.omitted_research_not_preserved == true,
  "The actual Classic runner must publish its honest reduced compiler profile")
local classic_mod_data = data.raw["mod-data"] or {}
local profile_transport = classic_mod_data["more-infinite-research-compiler-profile"]
local cap_transport = classic_mod_data["more-infinite-research-maximum-level-policy"]
if FIXTURE_TARGET == "f210" then
  check("CPR-15", profile_transport and profile_transport.data_type == "more-infinite-research.compiler-profile-v1"
      and profile_transport.data.profile_fingerprint == actual_profile.profile_fingerprint
      and cap_transport and cap_transport.data_type == "more-infinite-research.maximum-level-policy-v3"
      and cap_transport.data.schema == 3 and cap_transport.data.finalizer_status == "accepted",
    "The modern Classic selected plan must support the normal V3 cap and profile transports")
else
  check("CPR-15", profile_transport == nil and cap_transport == nil,
    "The F200 Classic path must not fabricate unavailable mod-data transports")
end
local forbidden_loaded = false
for _, name in ipairs(forbidden_classic_modules) do
  forbidden_loaded = forbidden_loaded or package.loaded[name] ~= nil
end
check("CPR-16", not forbidden_loaded,
  "The actual Classic planner and emitter must not load full registry, acquisition, recipe, or catalog modules")

if #failures > 0 then error(table.concat(failures, "\n"), 0) end

return {assertions = assertions, classic_calls = classic_calls, full_calls = full_calls,
  historic_full_calls = historic_full_calls}

-- Source-bound controls for the one preservation-capable compiler.
-- Saved `classic` selections remain accepted serialization values but execute
-- the sole Full data-final path. No retired compiler is allowed to load.

local assertions, failures = 0, {}
local function check(id, condition, detail)
  assertions = assertions + 1
  if not condition then failures[#failures + 1] = id .. ": " .. detail end
end

local PROFILE = "prototypes.mir.settings.compiler_profile"
local FINAL_STAGE = "prototypes.mir.stage.data_final_fixes"
local DATA_STAGE = "prototypes.mir.stage.data"
local RETIRED = "prototypes.mir.pipeline.classic_compiler"
local FULL = "prototypes.mir.pipeline.commands"
local TARGET = "prototypes.mir.platform.factorio.target_line"

local function unload(name)
  package.loaded[name] = nil
  package.preload[name] = nil
end

local function reset_final_stage()
  for _, name in ipairs({FINAL_STAGE, PROFILE, RETIRED, FULL, TARGET}) do unload(name) end
end

local function load_final_stage(saved_profile, factorio_version)
  reset_final_stage()
  _G.settings = {startup = saved_profile and { ["mir-compiler-profile"] = {value = saved_profile} } or {}}
  package.preload[TARGET] = function() return {factorio_version = factorio_version or "2.1"} end
  package.preload[RETIRED] = function() error("retired compiler was loaded", 0) end
  package.preload[FULL] = function()
    return {run_all = function(options) return {profile = "full", return_snapshot = options and options.return_snapshot} end}
  end
  return require(FINAL_STAGE)
end

local saved_classic = load_final_stage("classic")
local saved_result = saved_classic.run()
check("SCP-01", saved_result and saved_result.profile == "full" and saved_result.return_snapshot == false,
  "a saved Classic value must execute the complete Full stage")
check("SCP-02", package.loaded[RETIRED] == nil,
  "a saved Classic value must not load the retired compiler")

local default_stage = load_final_stage(nil)
local default_result = default_stage.run()
check("SCP-03", default_result and default_result.profile == "full" and default_result.return_snapshot == false,
  "an absent setting must retain the complete Full stage")
check("SCP-04", package.loaded[RETIRED] == nil,
  "the default path must not load the retired compiler")

local historic_stage = load_final_stage("classic", "0.18")
local historic_result = historic_stage.run()
check("SCP-05", historic_result and historic_result.profile == "full" and package.loaded[RETIRED] == nil,
  "historical package lines must retain their established Full-compatible path")

unload(PROFILE)
_G.settings = {startup = {}}
local profile = require(PROFILE)
local descriptor = profile.prototype()
check("SCP-06", profile.name == "mir-compiler-profile" and profile.get() == "full",
  "an absent serialized setting resolves to Full")
check("SCP-07", descriptor.type == "string-setting" and descriptor.setting_type == "startup"
  and descriptor.default_value == "full" and descriptor.hidden == true
  and descriptor.allowed_values[1] == "full" and descriptor.allowed_values[2] == "classic" and #descriptor.allowed_values == 2,
  "the hidden bridge must retain both serialized values without exposing a second compiler")
_G.settings = {startup = {["mir-compiler-profile"] = {value = "classic"}}}
check("SCP-08", profile.get() == "full", "the old raw Classic serialization must map to Full")
_G.settings = {startup = {["mir-compiler-profile"] = {value = "unsafe-unknown"}}}
local invalid_ok, invalid_reason = pcall(profile.get)
check("SCP-09", not invalid_ok and tostring(invalid_reason):find("Unsupported MIR compiler profile", 1, true) ~= nil,
  "an unknown serialized value must fail before any compiler dispatch")

unload(DATA_STAGE)
unload("prototypes.mir.streams.registry")
unload("prototypes.mir.platform.factorio.target_line")
unload("prototypes.mir.platform.factorio.data_raw")
unload("prototypes.mir.platform.factorio.mods")
local extended = {}
package.preload["prototypes.mir.streams.registry"] = function() error("stage.data imported the stream registry", 0) end
package.preload["prototypes.mir.platform.factorio.target_line"] = function()
  return {feature_enabled = function(name) return name == "research_library" end}
end
package.preload["prototypes.mir.platform.factorio.data_raw"] = function()
  return {extend = function(rows) for _, row in ipairs(rows) do extended[#extended + 1] = row end end}
end
package.preload["prototypes.mir.platform.factorio.mods"] = function() return {exists = function() return false end} end
local data_stage = require(DATA_STAGE)
data_stage.run()
check("SCP-10", #extended == 1 and extended[1].type == "shortcut"
  and extended[1].name == "mir-research-browser" and extended[1].icon == "__base__/graphics/icons/lab.png",
  "the Library shortcut remains available without a compiler catalogue")
check("SCP-11", package.loaded["prototypes.mir.streams.registry"] == nil,
  "the Library shortcut must not load the stream registry")

if #failures > 0 then error(table.concat(failures, "\n"), 0) end
return {assertions = assertions}

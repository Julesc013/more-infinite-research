-- The Research Library keeps its existing enrichment DTO when a save retains
-- the old hidden `classic` value.  It never loads or surfaces a reduced
-- compiler catalogue during a shortcut callback.

local assertions, failures = 0, {}
local function check(id, condition, detail)
  assertions = assertions + 1
  if not condition then failures[#failures + 1] = id .. ": " .. detail end
end

local PROVIDER = "prototypes.mir.runtime.research_browser_mir_provider"
local HOST = "prototypes.mir.platform.factorio.browser_host"
local CONTROL = "prototypes.mir.runtime.maximum_level_control"
local CATALOG = "prototypes.mir.settings.catalog"
local STARTUP = "prototypes.mir.runtime.startup_settings"
local CODEC = "prototypes.mir.settings.profile_codec"
local RETIRED_DECLARATIONS = "prototypes.mir.domain.compiler.classic_declarations"

local function unload(name)
  package.loaded[name] = nil
  package.preload[name] = nil
end

local function provider_for()
  for _, name in ipairs({PROVIDER, HOST, CONTROL, CATALOG, STARTUP, CODEC, RETIRED_DECLARATIONS}) do unload(name) end
  local collections = {mod_data = {}, mod_setting = {}}
  package.preload[RETIRED_DECLARATIONS] = function() error("retired declarations were loaded", 0) end
  package.preload[HOST] = function()
    return {prototype_collections = function() return collections end}
  end
  package.preload[CONTROL] = function()
    return {runtime_settings_bindings = function() return {} end}
  end
  package.preload[CATALOG] = function()
    return {spec = function() return nil end, validate_value = function() return false end}
  end
  package.preload[STARTUP] = function() return {get = function() return nil end} end
  package.preload[CODEC] = function()
    return {import_setting_name = "mir-settings-profile-import", decode = function() return nil end}
  end
  return require(PROVIDER), collections
end

_G.settings = {startup = {["mir-compiler-profile"] = {value = "classic"}}}
local provider, collections = provider_for()
local force = {valid = true, technologies = {}}
local parsing_require = require
require = function(name) error("[mir-browser-event-require] " .. tostring(name), 2) end
local listed_ok, listed = pcall(provider.list_snapshot, force)
local snapshot_ok, snapshot = pcall(provider.snapshot, force)
require = parsing_require
check("SCB-01", listed_ok and snapshot_ok,
  "Library enrichment must remain available after runtime module loading")
check("SCB-02", listed.compiler_scope == nil and snapshot.compiler_scope == nil,
  "a saved Classic value must not surface a retired reduced catalogue DTO")
check("SCB-03", package.loaded[RETIRED_DECLARATIONS] == nil,
  "Library callbacks must not load retired declarations")

collections.mod_data["more-infinite-research-compiler-profile"] = {
  data = {schema = 1, kind = "mir-classic-profile-public", profile = "classic"}
}
local ignored = provider.list_snapshot(force)
check("SCB-04", ignored.compiler_scope == nil,
  "stale reduced-profile transport must not recreate an alternate catalogue")

_G.settings = {startup = {["mir-compiler-profile"] = {value = "full"}}}
local full_provider = provider_for()
check("SCB-05", full_provider.list_snapshot(force).compiler_scope == nil
  and full_provider.snapshot(force).compiler_scope == nil,
  "the current Full selection retains the same no-scope Library DTO")

if #failures > 0 then error(table.concat(failures, "\n"), 0) end
return {assertions = assertions}

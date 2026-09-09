local anchor_name = "recipe-prod-research_material_tin-1"
local stream_key = "research_material_tin"
local profile_codec = require("__more-infinite-research__/prototypes/mir/settings/profile_codec")
local startup_settings = require("__more-infinite-research__/prototypes/mir/runtime/startup_settings")

local function fail(message) error("[mir-bob-tin-progression-frontier] " .. message) end

local function json(value)
  if type(value) == "string" then return "\"" .. value:gsub("\\", "\\\\"):gsub("\"", "\\\"") .. "\"" end
  if type(value) == "boolean" then return value and "true" or "false" end
  if type(value) == "number" then return tostring(value) end
  local keys, parts = {}, {}
  for key, _ in pairs(value) do table.insert(keys, key) end
  table.sort(keys)
  for _, key in ipairs(keys) do table.insert(parts, json(key) .. ":" .. json(value[key])) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function emit_runtime_observation()
  for _, name in ipairs({"base", "elevated-rails", "quality", "recycler", "space-age", "boblibrary", "bobores", "bobplates", "more-infinite-research"}) do
    if not script.active_mods[name] then fail("required exact F210 Bob closure mod absent " .. name) end
  end
  for _, name in ipairs({"angelssmelting", "angelsrefining", "angelspetrochem"}) do if script.active_mods[name] then fail("Bob-only runtime refuses Angel module " .. name) end end
  local prototype = prototypes.technology[anchor_name]
  if not prototype then fail("Tin anchor prototype is absent") end
  local profile = settings.startup["mir-settings-profile-import"]
  local decoded, profile_error = profile and profile_codec.decode(profile.value)
  local setting_name = "ips-max-level-" .. stream_key
  local imported = decoded and decoded.settings and decoded.settings[setting_name]
  if imported == nil then fail("MIRSET1 runtime profile does not decode: " .. tostring(profile_error)) end
  local raw_direct = startup_settings.raw(setting_name)
  local effective = startup_settings.get(setting_name)
  local tin_bindings = {}
  local policy = prototypes.mod_data["more-infinite-research-maximum-level-policy"]
  for _, row in ipairs((policy and policy.data and policy.data.bindings) or {}) do
    if row.technology == anchor_name then table.insert(tin_bindings, row) end
  end
  if #tin_bindings ~= 1 then fail("Tin maximum-level policy binding cardinality differs " .. tostring(#tin_bindings)) end
  local binding = tin_bindings[1]
  if binding.technology ~= anchor_name or binding.setting ~= setting_name or binding.selected ~= effective or binding.selected ~= imported then
    fail("Tin maximum-level policy binding differs from runtime cap/profile")
  end
  local force = game.forces.player
  local technology = force and force.technologies[anchor_name]
  if not technology then fail("Tin force technology is absent") end
  log("[mir-bob-tin-progression-frontier] RUNTIME JSON " .. json({
    technology = anchor_name,
    prototype_max_level = prototype.max_level == 4294967295 and "infinite" or prototype.max_level,
    native_prototype_max_level = prototype.max_level,
    raw_direct_max_level = raw_direct,
    mirset1_imported_max_level = imported,
    effective_max_level = effective,
    policy_technology = binding.technology,
    policy_setting = binding.setting,
    policy_selected = binding.selected,
    policy_binding_count = #tin_bindings,
    force_next_level = technology.level
  }))
end

script.on_init(emit_runtime_observation)
local emitted_after_load = false
script.on_event(defines.events.on_tick, function()
  if not emitted_after_load then
    emitted_after_load = true
    emit_runtime_observation()
  end
end)

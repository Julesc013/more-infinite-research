-- Controlled codec-API fixture for the actual profile codec and startup reader.
-- This does not measure Factorio performance or native serialization.
local assertions, decoded, parsed = 0, 0, 0
local function check(condition, message)
  assertions = assertions + 1
  if not condition then error(message) end
end
local allow_cap = true
package.preload["prototypes.mir.settings.catalog"] = function()
  return {
    import_setting_name = "mir-settings-profile-import",
    validate_value = function(name, value)
      if name == "cap" then return allow_cap and type(value) == "number" and value >= 0 and value <= 100 end
      if name == "enabled" then return type(value) == "boolean" end
      return false
    end
  }
end
local profiles = {
  ["json:first"] = {schema = 1, settings = {cap = 40, enabled = false, future = 80}},
  ["json:second"] = {schema = 1, settings = {cap = 60, enabled = true}},
  ["json:invalid-known"] = {schema = 1, settings = {cap = "invalid", enabled = true}},
  ['{"schema":1,"settings":{}}'] = {schema = 1, settings = {}}
}
local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end
local function codec_helpers()
  return {
    encode_string = function(value) return value end,
    decode_string = function(value) decoded = decoded + 1; return "json:" .. value end,
    json_to_table = function(value) parsed = parsed + 1; return copy(profiles[value]) end
  }
end
helpers = codec_helpers()
settings = {startup = {
  ["mir-settings-profile-import"] = {value = "MIRSET1:first"},
  cap = {value = 5}, enabled = {value = true}
}}
local reader = require("prototypes.mir.runtime.startup_settings")
check(reader.get("cap") == 40, "initial import was not applied")
check(reader.get("enabled") == false, "false import value was lost")
check(reader.get("future") == nil, "unregistered imported setting became available")
check(decoded == 1 and parsed == 1, "each setting lookup decoded the same profile again")
for _ = 1, 600 do assert(reader.get("cap") == 40, "repeated import changed value") end
check(decoded == 1 and parsed == 1, "repeated reads did not reuse one decoded profile")
check(reader.raw("cap") == 5, "raw startup access acquired imported precedence")
settings.startup.cap.value = 9
allow_cap = false
check(reader.get("cap") == 9, "cached profile bypassed current value validation")
allow_cap = true
check(reader.get("cap") == 40, "restored validation did not admit the current import")
settings.startup.cap = nil
check(reader.get("cap") == nil, "cached profile bypassed current registration")
settings.startup.cap = {value = 9}
check(reader.get("cap") == 40, "re-registered setting did not use current import")
settings.startup["mir-settings-profile-import"].value = "MIRSET1:second"
check(reader.get("cap") == 60 and reader.get("enabled") == true, "changed text retained old profile")
check(decoded == 2 and parsed == 2, "changed profile was not decoded exactly once")
settings.startup["mir-settings-profile-import"].value = "MIRSET1:invalid-known"
check(reader.get("cap") == 9 and reader.get("enabled") == true, "invalid known entry changed partial-import behavior")
check(decoded == 3 and parsed == 3, "invalid known values caused repeated decoding")
settings.startup["mir-settings-profile-import"].value = "MIRSET1:missing"
check(reader.get("cap") == 9 and reader.get("enabled") == true, "invalid profile did not retain raw values")
check(decoded == 4 and parsed == 4, "invalid decode was repeated instead of reused")
helpers = nil
settings.startup["mir-settings-profile-import"].value = "MIRSET1:first"
check(reader.get("cap") == 9, "unavailable helpers did not preserve raw fallback")
helpers = codec_helpers()
check(reader.get("cap") == 40 and decoded == 5 and parsed == 5, "helper availability left a stale failed decode")
helpers.json_to_table = function(value)
  parsed = parsed + 1
  local result = copy(profiles[value]); result.settings.cap = 70
  return result
end
check(reader.get("cap") == 70 and decoded == 6 and parsed == 6, "changed JSON API did not invalidate the decoded profile")
helpers.decode_string = function(_) decoded = decoded + 1; return "json:second" end
check(reader.get("cap") == 70 and reader.get("enabled") == true and decoded == 7 and parsed == 7, "changed decode API did not invalidate the decoded profile")
helpers.encode_string = function(value) return "changed:" .. value end
check(reader.get("enabled") == true and decoded == 8 and parsed == 8, "changed codec availability contract did not invalidate reuse")
local old = helpers
helpers = {json_to_table = old.json_to_table, decode_string = old.decode_string, encode_string = old.encode_string}
check(reader.get("cap") == 70 and decoded == 9 and parsed == 9, "changed helper identity retained prior environment cache")
helpers = codec_helpers()
settings.startup["mir-settings-profile-import"].value = '{"schema":1,"settings":{}}'
check(reader.get("cap") == 9 and reader.get("enabled") == true, "valid empty profile did not preserve direct values")
check(decoded == 9 and parsed == 10, "raw JSON profile was decoded through the compressed path or repeatedly parsed")
settings.startup["mir-settings-profile-import"].value = ""
check(reader.get("cap") == 9, "empty import did not preserve direct value")
settings.startup["mir-settings-profile-import"] = nil
check(reader.get("cap") == 9, "absent import did not preserve direct value")
profiles["json:zero"] = {schema = 1, settings = {cap = 0, enabled = false}}
settings.startup["mir-settings-profile-import"] = {value = "MIRSET1:zero"}
check(reader.get("cap") == 0 and reader.get("enabled") == false, "zero or false imported value became direct fallback")
check(reader.get("mir-settings-profile-import") == "MIRSET1:zero", "import setting was overridden by its own profile")
local input = "MIRSET1:first"
settings.startup["mir-settings-profile-import"].value = setmetatable({}, {__tostring = function() return input end})
check(reader.get("cap") == 40, "non-string input lost prior codec conversion")
input = "MIRSET1:second"
check(reader.get("cap") == 60, "non-string input reused a stale tostring conversion")
print("[ok] startup profile decode reuse passed " .. assertions .. " assertions; controlled codec APIs, no native performance claim")

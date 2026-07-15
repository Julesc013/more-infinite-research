local function fail(message)
  error("MIR settings profile round-trip validation failed: " .. message)
end

local function assert_equal(label, actual, expected)
  if actual ~= expected then
    fail(label .. " was " .. tostring(actual) .. ", expected " .. tostring(expected) .. ".")
  end
end

local function assert_true(label, value)
  if value ~= true then
    fail(label .. " was not true.")
  end
end

local function assert_nil(label, value)
  if value ~= nil then
    fail(label .. " was " .. tostring(value) .. ", expected nil.")
  end
end

local function startup_setting(name)
  return settings and settings.startup and settings.startup[name] or nil
end

local reduced_older_line = startup_setting("mir-prototype-speed-cap") == nil

if reduced_older_line then
  local function assert_startup_setting(name)
    if not startup_setting(name) then
      fail("Reduced older-line setting surface is missing " .. name .. ".")
    end
  end

  local function assert_no_startup_setting(name)
    if startup_setting(name) then
      fail("Reduced older-line setting surface unexpectedly includes " .. name .. ".")
    end
  end

  for _, name in ipairs({
    "ips-enable-research_character_reach",
    "ips-cost-base-research_character_reach",
    "mir-lab-incompatibility-policy",
    "mir-adjust-vanilla-weapon-speed-techs",
    "mir-enable-research-speed"
  }) do
    assert_startup_setting(name)
  end

  for _, name in ipairs({
    "ips-enable-research_gears",
    "ips-enable-research_air_scrubbing_clean_filter",
    "mir-pipeline-extent-multiplier",
    "mir-prototype-productivity-cap",
    "mir-prototype-efficiency-cap",
    "mir-prototype-pollution-cap",
    "mir-prototype-speed-cap",
    "mir-prototype-quality-cap",
    "mir-prototype-positive-power-floor",
    "mir-settings-profile-import",
    "mir-use-installed-space-age-icons"
  }) do
    assert_no_startup_setting(name)
  end

  local json = [[{"codec":"canonical-json-deflate-base64","format":1,"kind":"mir-settings-profile","schema":1,"settings":{"ips-cost-base-research_character_reach":12345,"ips-enable-research_character_reach":false,"mir-adjust-vanilla-weapon-speed-techs":"always","mir-lab-incompatibility-policy":"skip"}}]]
  local encoded_a = "MIRSET1-unavailable-on-reduced-line:" .. json
  local encoded_b = "MIRSET1-unavailable-on-reduced-line:" .. json
  assert_equal("deterministic local profile payload", encoded_b, encoded_a)

  local continuation_locale = {
    ["braking-force"] = "braking-force",
    ["research-speed"] = "research-speed",
    ["worker-robots-storage"] = "worker-robots-storage",
    ["weapon-shooting-speed"] = "weapon-shooting-speed",
    ["laser-turret-speed"] = "laser-turret-speed"
  }

  local function assert_localised_reference(label, value, expected_key)
    if type(value) ~= "table" then
      fail(label .. " does not have an explicit localised string.")
    end
    assert_equal(label .. " locale key", value[1], expected_key)
  end

  for chain_key, locale_key in pairs(continuation_locale) do
    local highest
    for name, tech in pairs(data.raw.technology or {}) do
      local level = tonumber(string.match(name, "^" .. chain_key:gsub("([^%w])", "%%%1") .. "%-(%d+)$"))
      if level and tech.max_level == "infinite" and (not highest or level > highest.level) then
        highest = {
          level = level,
          name = name,
          tech = tech
        }
      end
    end
    if highest then
      assert_localised_reference(highest.name .. " localised_name", highest.tech.localised_name, "technology-name." .. locale_key)
      assert_localised_reference(highest.name .. " localised_description", highest.tech.localised_description, "technology-description." .. locale_key)
    end
  end
  return
end

local settings_catalog = require("__more-infinite-research__.prototypes.mir.settings.catalog")
local profile_codec = require("__more-infinite-research__.prototypes.mir.settings.profile_codec")

local valid_profile = {
  schema = profile_codec.schema,
  kind = profile_codec.kind,
  mod = "more-infinite-research",
  metadata = {
    fixture = "settings-profile-roundtrip"
  },
  settings = {
    ["ips-enable-research_air_scrubbing_clean_filter"] = false,
    ["ips-cost-base-research_tungsten"] = 12345,
    ["mir-pipeline-extent-multiplier"] = "500",
    ["mir-prototype-efficiency-cap"] = "saving-9999",
    ["mir-prototype-pollution-cap"] = "saving-9999",
    ["mir-prototype-positive-power-floor"] = true
  }
}

local encoded_a, err_a = profile_codec.encode(valid_profile)
if not encoded_a then fail("valid profile did not encode: " .. tostring(err_a)) end
local encoded_b, err_b = profile_codec.encode(valid_profile)
if not encoded_b then fail("valid profile did not encode a second time: " .. tostring(err_b)) end
assert_equal("deterministic encoded profile", encoded_b, encoded_a)

local decoded, decode_err = profile_codec.decode(encoded_a)
if not decoded then fail("encoded profile did not decode: " .. tostring(decode_err)) end
assert_equal("decoded efficiency cap", decoded.settings["mir-prototype-efficiency-cap"], "saving-9999")
assert_equal("decoded pollution cap", decoded.settings["mir-prototype-pollution-cap"], "saving-9999")
assert_equal("decoded hidden provider setting", decoded.settings["ips-enable-research_air_scrubbing_clean_filter"], false)

local recognized, unknown, invalid = profile_codec.count_recognized_settings(decoded)
assert_equal("recognized valid profile settings", recognized, 6)
assert_equal("unknown valid profile settings", unknown, 0)
assert_equal("invalid valid profile settings", invalid, 0)

local compact_profile = profile_codec.current_profile({
  compact = true,
  names = {
    "mir-prototype-productivity-cap",
    "mir-prototype-efficiency-cap",
    "mir-prototype-positive-power-floor"
  },
  value_resolver = function(name)
    if name == "mir-prototype-efficiency-cap" then return "saving-9999" end
    return settings_catalog.default_value(name)
  end
})
assert_nil("compact default productivity cap", compact_profile.settings["mir-prototype-productivity-cap"])
assert_nil("compact default positive power floor", compact_profile.settings["mir-prototype-positive-power-floor"])
assert_equal("compact non-default efficiency cap", compact_profile.settings["mir-prototype-efficiency-cap"], "saving-9999")

local invalid_profile = {
  schema = profile_codec.schema,
  kind = profile_codec.kind,
  settings = {
    ["ips-enable-research_air_scrubbing_clean_filter"] = false,
    ["ips-cost-base-research_tungsten"] = "wrong-type",
    ["mir-pipeline-extent-multiplier"] = "1000",
    ["mir-prototype-efficiency-cap"] = "saving-100000",
    ["mir-fixture-unknown-setting"] = true
  }
}

local invalid_status = profile_codec.profile_status(invalid_profile)
assert_equal("recognized invalid-profile settings", invalid_status.recognized, 1)
assert_equal("invalid invalid-profile settings", invalid_status.invalid, 3)
assert_equal("unknown invalid-profile settings", invalid_status.unknown, 1)

local speed_legacy_ok = settings_catalog.validate_value("mir-prototype-speed-cap", "bonus-100000")
assert_true("legacy speed import cap remains accepted", speed_legacy_ok)

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

local function assert_close(label, actual, expected)
  if type(actual) ~= "number" or math.abs(actual - expected) > 0.0000001 then
    fail(label .. " was " .. tostring(actual) .. ", expected " .. tostring(expected) .. ".")
  end
end

local function assert_nil(label, value)
  if value ~= nil then
    fail(label .. " was " .. tostring(value) .. ", expected nil.")
  end
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
    ["mir-pipeline-extent-multiplier"] = 123.45,
    ["mir-prototype-productivity-cap"] = 4321.5,
    ["mir-recycling-return-chance"] = 12.34,
    ["mir-prototype-efficiency-cap"] = -83.25,
    ["mir-prototype-pollution-cap"] = -91.125,
    ["mir-prototype-speed-cap"] = 1234.5,
    ["mir-prototype-quality-cap"] = 678.9,
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
assert_equal("decoded custom pipeline percentage", decoded.settings["mir-pipeline-extent-multiplier"], 123.45)
assert_equal("decoded custom productivity percentage", decoded.settings["mir-prototype-productivity-cap"], 4321.5)
assert_equal("decoded custom recycler percentage", decoded.settings["mir-recycling-return-chance"], 12.34)
assert_equal("decoded custom efficiency percentage", decoded.settings["mir-prototype-efficiency-cap"], -83.25)
assert_equal("decoded custom pollution percentage", decoded.settings["mir-prototype-pollution-cap"], -91.125)
assert_equal("decoded hidden provider setting", decoded.settings["ips-enable-research_air_scrubbing_clean_filter"], false)

local recognized, unknown, invalid = profile_codec.count_recognized_settings(decoded)
assert_equal("recognized valid profile settings", recognized, 10)
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
    ["mir-pipeline-extent-multiplier"] = "2000",
    ["mir-prototype-efficiency-cap"] = "saving-100000",
    ["mir-prototype-productivity-cap"] = -1,
    ["mir-recycling-return-chance"] = 25.1,
    ["mir-fixture-unknown-setting"] = true
  }
}

local invalid_status = profile_codec.profile_status(invalid_profile)
assert_equal("recognized invalid-profile settings", invalid_status.recognized, 1)
assert_equal("invalid invalid-profile settings", invalid_status.invalid, 5)
assert_equal("unknown invalid-profile settings", invalid_status.unknown, 1)

local speed_legacy_ok = settings_catalog.validate_value("mir-prototype-speed-cap", "bonus-100000")
assert_true("legacy speed import cap remains accepted", speed_legacy_ok)
local recycler_legacy_ok = settings_catalog.validate_value("mir-recycling-return-chance", "percent-25")
assert_true("legacy fixed 25 percent recycler import remains accepted", recycler_legacy_ok)
local recycler_spec = settings_catalog.spec("mir-recycling-return-chance")
for _, value in ipairs((recycler_spec and recycler_spec.allowed_values) or {}) do
  if value == "percent-25" then
    fail("fixed 25 percent recycler value should not be visible in the dropdown")
  end
end

local pipeline_extent = require("__more-infinite-research__.prototypes.mir.settings.pipeline_extent")
local prototype_limits = require("__more-infinite-research__.prototypes.mir.settings.prototype_limits")
assert_close("custom pipeline percentage parse", pipeline_extent.parse(123.45), 1.2345)
assert_close("custom productivity percentage parse", prototype_limits.value("productivity", 4321.5), 43.215)
assert_close("custom efficiency percentage parse", prototype_limits.value("efficiency", -83.25), -0.8325)
assert_close("custom recycler percentage parse", prototype_limits.recycling_return_value(12.34, nil), 0.1234)

"""MIRSET1 settings-profile host controls (Lua 5.2; not native evidence)."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SettingsProfileTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          decoded, reports = {}, {}
          helpers = {
            encode_string = function(text) last_encoded = text; return text end,
            decode_string = function(text)
              if text == "bad-decode" then return nil end
              return text
            end,
            json_to_table = function(text) return decoded[text] end,
            game_version = "2.1.23"
          }
          script = {active_mods = {['more-infinite-research'] = '5.0.0-draft'}}
          config = require("research.settings")
          codec = require("research.settings_profile")
          facade = require("runtime.settings_profile")
          function defaults()
            local out = {}
            for _, spec in ipairs(config.prototypes()) do out[spec.name] = {value = spec.default_value} end
            return out
          end
          settings = {startup = defaults()}
        ''')

    def test_registered_settings_are_the_single_active_profile_authority(self):
        self.lua.execute(r'''
          local prototypes, names = config.prototypes(), config.registered_names()
          -- The profile import transport is the one non-exportable descriptor.
          -- The other 888 shipped startup descriptors are the complete F210
          -- Base/Space Age settings closure, including retained identities.
          assert(#prototypes == 889 and #names == 888)
          assert(prototypes[1].name == config.import_setting_name)
          local found, prototype_by_name, type_count = {}, {}, {}
          for _, prototype in ipairs(prototypes) do
            assert(not prototype_by_name[prototype.name])
            prototype_by_name[prototype.name] = prototype
            type_count[prototype.type] = (type_count[prototype.type] or 0) + 1
          end
          assert(type_count["bool-setting"] == 135)
          assert(type_count["int-setting"] == 499)
          assert(type_count["double-setting"] == 240)
          assert(type_count["string-setting"] == 15)
          for _, name in ipairs(names) do
            assert(not found[name] and prototype_by_name[name])
            found[name] = true
            local spec = config.spec(name)
            assert(spec and spec.name == name)
            assert(config.default_value(name) == spec.default_value)
            assert(config.validate_value(name, spec.default_value))
          end
          assert(not found[config.import_setting_name])
          assert(found["ips-enable-research_gears"])
          assert(found["ips-enable-research_agricultural_growth_speed"])
          assert(found["ips-enable-research_artificial_soil"])
          assert(found["mir-enable-braking-force"])
          assert(found["mir-max-level-worker-robots-speed"])
          assert(found["mir-enable-passive-repair"])
          assert(found["mir-unrestricted-modules"])
          assert(config.default_value("mir-enable-passive-repair") == false)
          assert(config.default_value("mir-unrestricted-modules") == false)
          local growth
          for _, spec in ipairs(prototypes) do
            if spec.name == "ips-cost-growth-research_gears" then growth = spec end
          end
          assert(growth and growth.maximum_value == 1000 and growth.minimum_value == 1)
          assert(growth.localised_name[1] == "mod-setting-name.ips-cost-growth-stream")
          local valid, reason = config.validate_value("ips-cost-growth-research_gears", 1001)
          assert(not valid and reason == "above maximum")
          assert(config.validate_value("ips-cost-growth-research_gears", 1000))
        ''')

    def test_direct_growth_ceiling_refuses_before_construction_and_keeps_native_zero_inheritance(self):
        self.lua.execute(r'''
          local normal = "ips-cost-growth-research_gears"
          local inherited = "mir-cost-growth-inserter-capacity-bonus"

          settings.startup[normal].value = 1001
          local ok, message = pcall(config.resolve, settings.startup)
          assert(not ok and string.find(message, "MIR invalid effective setting: " .. normal, 1, true))
          -- Resolution rejects the direct setting; it does not clamp or invoke
          -- a constructor with a different value.
          assert(settings.startup[normal].value == 1001)

          settings.startup[normal].value = 1000
          settings.startup[inherited].value = 0
          local values = config.resolve(settings.startup)
          assert(values.streams.research_gears.growth_factor == 1000)
          local gears = require("research.productivity").gears(values)
          assert(type(gears.unit.count_formula) == "string"
            and gears.unit.count_formula:find("1000", 1, true))

          -- Zero remains the named native-continuation inheritance sentinel.
          local continuation
          for _, row in ipairs(require("compatibility.modern_catalogue").continuations({})) do
            if row.id == "inserter-capacity-bonus-8" then continuation = row end
          end
          assert(continuation and values.native_continuations[continuation.family].growth_factor == 0)
          local output = require("research.modern").continuation(continuation, values)
          assert(type(output.unit.count_formula) == "string" and not output.unit.count_formula:find("nan", 1, true))
        ''')

    def test_import_precedence_uses_profile_validation_before_consumer_normalization(self):
        self.lua.execute(r'''
          settings.startup["ips-cost-base-research_gears"].value = 100
          settings.startup["ips-cost-growth-research_gears"].value = 2
          settings.startup["mir-unrestricted-modules"].value = true
          settings.startup[config.import_setting_name].value = "MIRSET1:incoming"
          decoded.incoming = {schema=1, kind="mir-settings-profile", settings={
            ["ips-enable-research_gears"] = false,
            ["ips-cost-base-research_gears"] = 777,
            ["ips-cost-growth-research_gears"] = 1001,
            ["ips-research-time-research_gears"] = 0,
            ["mir-enable-passive-repair"] = true,
            ["mir-unrestricted-modules"] = false
          }}
          local effective = config.effective_values(settings.startup, helpers)
          local result = config.resolve(settings.startup, helpers)
          assert(effective["ips-cost-base-research_gears"] == 777)
          assert(effective["ips-cost-growth-research_gears"] == 2)
          assert(effective["ips-research-time-research_gears"] == 0)
          assert(result.enabled == false and result.base_cost == 777 and result.growth_factor == 2)
          assert(result.research_time == 60 and result.passive_repair_enabled == true)
          assert(result.unrestricted_modules == false)
          assert(settings.startup[config.import_setting_name].value == "MIRSET1:incoming")
        ''')

    def test_malformed_import_falls_back_without_executing_input(self):
        self.lua.execute(r'''
          settings.startup["ips-cost-base-research_gears"].value = 345
          settings.startup[config.import_setting_name].value = "MIRSET1:missing"
          local result = config.resolve(settings.startup, helpers, function(message) reports[#reports + 1] = message end)
          assert(result.base_cost == 345 and #reports == 1)
          assert(reports[1] == "[more-infinite-research] Ignoring invalid MIR settings profile import")
        ''')

    def test_codec_has_canonical_identity_and_strict_compact_option(self):
        self.lua.execute(r'''
          local full = codec.current_profile({
            names = {"ips-cost-base-research_gears", "mir-enable-passive-repair"},
            value_resolver = function(name)
              if name == "ips-cost-base-research_gears" then return 8000 end
              return false
            end,
            is_default = config.is_default_value,
            compact = 1,
            metadata = {z = "last", a = "first"}
          })
          assert(full.metadata.export_mode == "full" and codec.count_settings(full) == 2)
          local compact = codec.current_profile({
            names = {"ips-cost-base-research_gears", "mir-enable-passive-repair"},
            value_resolver = function(name)
              if name == "ips-cost-base-research_gears" then return 8000 end
              return true
            end,
            is_default = config.is_default_value,
            compact = true
          })
          assert(compact.metadata.export_mode == "compact" and codec.count_settings(compact) == 1)
          local wire, err = codec.encode(full, helpers)
          assert(not err and wire:sub(1, 8) == "MIRSET1:")
          assert(last_encoded:find('"codec":"canonical-json-deflate-base64"', 1, true))
          assert(last_encoded:find('"format":1', 1, true))
          assert(last_encoded:find('"kind":"mir-settings-profile"', 1, true))
          assert(last_encoded:find('"schema":1', 1, true))
          local profile, decode_error = codec.decode("MIRSET1:", helpers)
          assert(profile == nil and decode_error == "empty")
          profile, decode_error = codec.decode("not-a-profile", helpers)
          assert(profile == nil and decode_error == "unsupported profile format")
        ''')

    def test_runtime_facade_exports_effective_values_and_reports_read_only_counts(self):
        self.lua.execute(r'''
          settings.startup[config.import_setting_name].value = "MIRSET1:effective"
          decoded.effective = {schema=1, settings={
            ["ips-cost-base-research_gears"] = 901,
            ["mir-enable-passive-repair"] = true,
            ["mir-unrestricted-modules"] = true
          }}
          local wire, err = facade.export_string({compact = false})
          assert(not err and wire:sub(1, 8) == "MIRSET1:")
          assert(last_encoded:find('"ips%-cost%-base%-research_gears":901'))
          assert(last_encoded:find('"mir%-enable%-passive%-repair":true'))
          assert(last_encoded:find('"mir%-unrestricted%-modules":true'))
          local settings_part = last_encoded:sub(assert(last_encoded:find('"settings":{', 1, true)))
          assert(not settings_part:find(config.import_setting_name, 1, true))
          decoded.status = {schema=1, settings={
            ["ips-cost-base-research_gears"] = 901,
            ["ips-cost-growth-research_gears"] = 1001,
            [config.import_setting_name] = "ignored",
            unknown = 1
          }}
          local status = facade.validate_string("MIRSET1:status")
          assert(status.valid and status.recognized == 1 and status.invalid == 1 and status.unknown == 2)
          assert(status.import_setting == config.import_setting_name)
          local invalid = facade.validate_string("MIRSET1:bad-decode")
          assert(invalid.valid == false and invalid.error == "profile string decoding failed")
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(SettingsProfileTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

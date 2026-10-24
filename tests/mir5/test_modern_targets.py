"""Selected modern native capabilities; no engine or historical pass claimed."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ModernTargetTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          target = require("platform.target")
          package.preload["__more-infinite-research__/platform/target"] = function() return target end
          catalogue = require("compatibility.modern_catalogue")
          function f200()
            target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"
            target.distribution_version, target.cargo_research = "5.0.20000", false
            target.recipe_probability, target.receiver_limits = "probability", false
            target.productivity_ignores_stats = true
          end
          function names(rows)
            local out = {}
            for _, row in ipairs(rows) do out[row.key] = row end
            return out
          end
        ''')

    def test_only_two_actual_cargo_modifiers_are_absent_in_f200(self):
        self.lua.execute('''
          local modern = catalogue.select({["space-age"]="2.1.23"})
          local existing = names(modern.definitions)
          assert(#modern.definitions == 62 and existing.research_cargo_landing_pad_count
            and existing.research_cargo_bay_unloading_distance)
          f200()
          local historical = catalogue.select({["space-age"]="2.0.77"})
          local selected = names(historical.definitions)
          assert(#historical.definitions == 60 and not selected.research_cargo_landing_pad_count
            and not selected.research_cargo_bay_unloading_distance)
          for key in pairs(existing) do
            if key ~= "research_cargo_landing_pad_count" and key ~= "research_cargo_bay_unloading_distance" then
              assert(selected[key], "unrelated family removed: " .. key)
            end
          end
          assert(#modern.definitions == 62 and existing.research_cargo_landing_pad_count)
          local molten = selected.research_molten_metals.effects
          assert(molten[1].recipe == "molten-copper-from-lava" and molten[1].scale == 1)
          assert(molten[2].recipe == "molten-iron-from-lava" and molten[2].scale == 1)
          assert(#molten == 2, "2.0 must retain the published lava-only effect scope")
          assert(existing.research_molten_metals.effects[3].recipe == "copper-ore-melting"
            and existing.research_molten_metals.effects[4].recipe == "iron-ore-melting")
          local base = catalogue.select({})
          assert(#base.definitions == 47 and names(base.definitions).research_science_pack_productivity)
          for _, row in ipairs(historical.definitions) do
            for _, effect in ipairs(row.effects) do
              assert(effect.type ~= "cargo-landing-pad-count" and effect.type ~= "max-cargo-bay-unloading-distance")
            end
          end
        ''')

    def test_f200_keeps_875_settings_and_supported_nondefault_values(self):
        self.lua.execute('''
          f200()
          mods = {base="2.0.77", ["space-age"]="2.0.77"}
          local config = require("research.settings")
          local descriptors = config.prototypes()
          assert(#descriptors == 875)
          assert(config.spec("ips-enable-research_cargo_landing_pad_count") == nil)
          assert(config.spec("ips-effect-per-level-research_cargo_bay_unloading_distance") == nil)
          assert(config.spec("ips-enable-research_platform") ~= nil)
          local values = config.resolve({["ips-effect-per-level-research_gears"]={value=17},
            ["mir-recycling-return-chance"]={value="percent-20"}})
          assert(values.effect_percent == 17 and values.options["mir-recycling-return-chance"] == "percent-20")
        ''')

    def test_f200_api_rejects_unsupported_cargo_effects_before_native_access(self):
        self.lua.execute('''
          f200()
          package.preload["__more-infinite-research__/research/generator"] = function()
            return require("research.generator")
          end
          local api = assert(loadfile(player_root .. "/api/v1/data.lua"))()
          data = setmetatable({}, {__index=function() error("unsupported native access") end})
          for _, kind in ipairs({"cargo-landing-pad-count", "max-cargo-bay-unloading-distance"}) do
            local ok, message = pcall(api.add_technology, {type="technology", name="consumer",
              effects={{type=kind, modifier=1}}})
            assert(not ok and tostring(message):find("MIR_API:unsupported_capability",1,true), tostring(message))
            ok, message = pcall(api.add_productivity, {type="technology", name="consumer",
              effects={{type=kind, modifier=1}}}, {"iron-gear-wheel"}, 0.1)
            assert(not ok and tostring(message):find("MIR_API:unsupported_capability",1,true), tostring(message))
          end
          assert(api.get_version().product == "5.0.20000" and api.get_capabilities().recipe_productivity)
        ''')

    def test_capability_check_keeps_typed_errors_for_malformed_effects(self):
        self.lua.execute('''
          package.preload["__more-infinite-research__/research/generator"] = function()
            return require("research.generator")
          end
          local api = assert(loadfile(player_root .. "/api/v1/data.lua"))()
          data = setmetatable({}, {__index=function() error("malformed native access") end})
          for _, effects in ipairs({false, 5, "bad", {5}, {[2]={type="laboratory-speed",modifier=0.1}}}) do
            local ok, message = pcall(api.add_technology, {type="technology",name="consumer",effects=effects})
            assert(not ok and tostring(message):find("MIR_API:invalid_definition",1,true), tostring(message))
          end
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ModernTargetTests))
    sys.exit(0 if result.wasSuccessful() else 1)

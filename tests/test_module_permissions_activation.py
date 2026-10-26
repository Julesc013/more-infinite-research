"""Data-stage activation controls for mir-unrestricted-modules (Lua 5.2 only)."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ModulePermissionsActivationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.globals().final_fixes = (ROOT / "source/data-final-fixes.lua").as_posix()
        self.lua.execute(r"""
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          config = require("research.settings")
          modern_catalogue = require("compatibility.modern_catalogue")
          mods = {base = "2.1.23"}

          function defaults()
            local out = {}
            for _, spec in ipairs(config.prototypes()) do
              out[spec.name] = {value = spec.default_value}
            end
            return out
          end

          function complete_world()
            -- Build only the current explicit base selection. This fixture
            -- remains a narrow override probe while satisfying the generator's
            -- named preflight without a data.raw discovery scan.
            local packs, technologies, recipe = {}, {}, {
              ["iron-gear-wheel"] = {foreign = "gear"},
              target = {foreign = "recipe", allow_speed = false,
                allowed_module_categories = {"narrow"}}
            }
            local function add_technology(name)
              if name then technologies[name] = technologies[name] or {} end
            end
            local function add_science(vector)
              for _, name in ipairs(modern_catalogue.science_names(vector)) do
                packs[name] = {}; add_technology(name)
              end
            end
            local selected = modern_catalogue.select(mods)
            for _, definition in ipairs(selected.definitions) do
              add_science(definition.science)
              for _, name in ipairs(definition.prerequisites) do add_technology(name) end
              for _, effect in ipairs(definition.effects) do
                if effect.recipe then recipe[effect.recipe] = {} end
              end
            end
            for _, continuation in ipairs(selected.continuations) do
              add_science(continuation.science)
              for _, name in ipairs(continuation.prerequisites) do add_technology(name) end
            end
            for _, name in ipairs({"automation", "logistic", "chemical", "production", "military", "utility"}) do
              packs[name .. "-science-pack"] = {}; add_technology(name .. "-science-pack")
            end
            local lab = {module_slots = 1, foreign = "receiver",
              allowed_effects = {"speed"}, allowed_module_categories = {"narrow"}}
            lab.inputs = {}
            for name in pairs(packs) do lab.inputs[#lab.inputs + 1] = name end
            table.sort(lab.inputs)
            return {
              raw = {
                technology = technologies,
                tool = packs,
                recipe = recipe,
                ["module-category"] = {speed = {}, custom = {}},
                module = {quality_module = {category = "quality"}},
                lab = {lab = lab}
              },
              writes = 0,
              extend = function(self, prototypes)
                self.writes = self.writes + 1
                self.emitted = prototypes
              end
            }
          end

          function run_final_fixes()
            return assert(loadfile(final_fixes))()
          end
        """)

    def test_disabled_setting_never_loads_override_or_reads_raw(self):
        self.lua.execute(r"""
          settings = {startup = defaults()}
          helpers = nil
          log = nil
          local raw = setmetatable({}, {
            __index = function(_, key) error("unexpected disabled raw read: " .. tostring(key)) end,
            __pairs = function() error("unexpected disabled raw enumeration") end
          })
          data = {raw = raw}
          local installs = 0
          package.loaded["research.productivity"] = nil
          package.loaded["research.generator"] = nil
          package.loaded["compatibility.gear_bindings"] = nil
          package.loaded["compatibility.modern_catalogue"] = nil
          package.loaded["research.modern"] = nil
          package.loaded["overrides.module_permissions"] = nil
          -- Isolate the independent research path: its named recipe preflight
          -- is covered by the Generator tests, not this inactive override test.
          package.preload["compatibility.gear_bindings"] = function()
            return {select = function(active_mods, prototypes)
              assert(active_mods == mods and prototypes == raw)
              return {icon = "stub", recipes = {"stub"}}
            end}
          end
          package.preload["research.productivity"] = function()
            return {gears = function(values)
              assert(values.unrestricted_modules == false)
              return {type = "technology", name = "stub"}
            end}
          end
          package.preload["compatibility.modern_catalogue"] = function()
            return {is_k2_base = function(active_mods)
              assert(active_mods == mods)
              return false
            end, is_k2so = function(active_mods)
              assert(active_mods == mods)
              return false
            end, retains_bob_native_continuations = function(active_mods)
              assert(active_mods == mods)
              return false
            end, select = function(active_mods)
              assert(active_mods == mods)
              return {definitions = {}, continuations = {}, recipe_patches = {}}
            end}
          end
          package.preload["research.modern"] = function()
            return {
              preflight_recipe_patches = function(selection, prototypes)
                assert(selection.recipe_patches[1] == nil and prototypes == raw)
              end,
              preflight_native_owner_patches = function(selection, prototypes)
                assert(selection.native_owners == nil and prototypes == raw)
                return {}
              end,
              technologies = function(selection) assert(#selection.definitions == 0); return {} end,
              apply_weapon_speed_overlap = function(selection, generated)
                assert(#selection.definitions == 0 and #generated == 0)
              end,
              apply_native_owner_patches = function(patches) assert(#patches == 0) end,
              apply_recipe_patches = function(selection, prototypes)
                assert(selection.recipe_patches[1] == nil and prototypes == raw)
              end
            }
          end
          package.preload["research.generator"] = function()
            return {install = function(prototypes, stage)
              assert(#prototypes == 1 and prototypes[1].name == "stub" and stage == data)
              installs = installs + 1
            end}
          end
          package.preload["overrides.module_permissions"] = function()
            error("disabled setting loaded override")
          end

          run_final_fixes()
          assert(installs == 1)
          assert(package.loaded["overrides.module_permissions"] == nil)
        """)

    def test_raw_true_applies_published_permissions_without_changing_gear_emission(self):
        self.lua.execute(r"""
          settings = {startup = defaults()}
          settings.startup["mir-unrestricted-modules"].value = true
          helpers, log = nil, nil
          data = complete_world()

          run_final_fixes()

          local gear = data.emitted[1]
          assert(data.writes == 1 and gear.name == "recipe-prod-research_gears-1" and gear.enabled ~= false)
          assert(gear.unit.count_formula == "8000*2^(L-1)" and gear.effects[1].change == .1)
          local recipe, lab = data.raw.recipe.target, data.raw.lab.lab
          assert(recipe.foreign == "recipe" and recipe.allow_speed and recipe.allow_productivity)
          assert(recipe.allow_consumption and recipe.allow_pollution and recipe.allow_quality)
          assert(#recipe.allowed_module_categories == 3)
          assert(recipe.allowed_module_categories[1] == "custom")
          assert(recipe.allowed_module_categories[2] == "quality")
          assert(recipe.allowed_module_categories[3] == "speed")
          assert(lab.foreign == "receiver" and #lab.allowed_effects == 5)
          assert(lab.allowed_effects[1] == "speed" and lab.allowed_effects[5] == "quality")
          assert(#lab.allowed_module_categories == 3)
        """)

    def test_profile_true_overrides_raw_false_and_applies_permissions(self):
        self.lua.execute(r"""
          settings = {startup = defaults()}
          settings.startup["mir-unrestricted-modules"].value = false
          settings.startup[config.import_setting_name].value = "MIRSET1:modules"
          helpers = {
            encode_string = function(text) return text end,
            decode_string = function(text) return text end,
            json_to_table = function(text)
              if text == "modules" then
                return {schema = 1, kind = "mir-settings-profile",
                  settings = {["mir-unrestricted-modules"] = true}}
              end
            end
          }
          log = nil
          assert(config.resolve(settings.startup, helpers).unrestricted_modules == true)
          data = complete_world()

          run_final_fixes()

          assert(data.writes == 1)
          assert(data.raw.recipe.target.allow_productivity == true)
          assert(data.raw.lab.lab.allowed_module_categories[1] == "custom")
        """)

    def test_source_keeps_override_loading_inside_strict_effective_branch(self):
        source = (ROOT / "source/data-final-fixes.lua").read_text(encoding="utf-8")
        branch = source.index("if values.unrestricted_modules == true then")
        require = source.index('require("overrides.module_permissions")')
        self.assertLess(branch, require)
        self.assertNotIn("prototypes/mir/", source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(ModulePermissionsActivationTests))
    sys.exit(0 if result.wasSuccessful() else 1)

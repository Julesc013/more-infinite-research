"""Host controls for the private F210 override-interaction native fixture.

They validate only fixture-owned probes and the public F210 API surface; no
Factorio process is launched here.
"""
import argparse
import json
import os
from pathlib import Path
import re
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/override-interactions"
PROFILE = ROOT / "tests/profiles/override-interactions-f210-2123.json"
F210_RUNTIME_API_CANDIDATES = (
    os.environ.get("MIR_F210_RUNTIME_API"),
    "D:/Games/Steam/steamapps/common/Factorio/doc-html/runtime-api.json",
    "C:/Program Files/Steam/steamapps/common/Factorio/doc-html/runtime-api.json",
)


def f210_runtime_api_path():
    for candidate in F210_RUNTIME_API_CANDIDATES:
        if candidate:
            path = Path(candidate)
            if path.is_file():
                return path
    return None


class OverrideInteractionsFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().stage_path = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.globals().control_path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().settings_path = (FIXTURE / "settings-updates.lua").as_posix()
        self.lua.globals().data_path = (FIXTURE / "data.lua").as_posix()
        runner = (ROOT / "tools/Invoke-NativeFixture.ps1").read_text(encoding="utf-8")
        completed_save = re.findall(r"\$complete=Join-Path \$writeData 'saves/([^'/]+)\.zip'", runner)
        self.assertEqual(1, len(completed_save), "native runner must have one completed-save contract")
        self.lua.globals().expected_complete_save = completed_save[0]
        self.lua.execute(r'''
          function stage_fixture(opponent)
            local categories = {speed={}, ["mir5-override-module-category"]={}}
            local ordinary = {
              maximum_productivity=1, energy_required=.5, enabled=true,
              allow_speed=true, allow_productivity=true, allow_consumption=true,
              allow_pollution=true, allow_quality=true,
              allowed_module_categories={"mir5-override-module-category", "speed"}
            }
            local recycled = {maximum_productivity=.5, hidden=true, unlock_results=false,
              results={{type="item", name="iron-plate", amount=1, independent_probability=.2}}}
            local parameter = {parameter=true, allow_speed=false, allow_productivity=false,
              allow_consumption=false, allow_pollution=false, allow_quality=false,
              allowed_module_categories={"speed"}}
            local receiver = {base_effect={speed=0}, uses_module_effects=true,
              uses_beacon_effects=true, uses_surface_effects=true,
              speed_limits={low=-.5, high=2}, quality_limits={low=0, high=1}}
            local machine = {allowed_effects={"speed", "productivity", "consumption", "pollution", "quality"},
              allowed_module_categories={"mir5-override-module-category", "speed"},
              module_slots=2, crafting_speed=1, energy_usage="1W", effect_receiver=receiver}
            local pipeline = {fluid_boxes={{max_pipeline_extent=480}, {max_pipeline_extent=480}}}
            if opponent == "ordinary-cap" then ordinary.maximum_productivity=.5 end
            if opponent == "recycling-field" then recycled.results[1].probability=.2; recycled.results[1].independent_probability=nil end
            if opponent == "parameter" then parameter.allow_productivity=true end
            if opponent == "receiver" then receiver.speed_limits.high=3 end
            if opponent == "pipeline" then pipeline.fluid_boxes[2].max_pipeline_extent=320 end
            if opponent == "power" then machine.energy_usage="0kW" end
            local env = {data={raw={
              ["module-category"]=categories,
              module={fixture={category="mir5-override-module-category"}},
              recipe={["mir5-override-ordinary"]=ordinary, ["mir5-override-recycling"]=recycled,
                ["mir5-override-parameter"]=parameter},
              ["assembling-machine"]={["mir5-override-assembler"]=machine,
                ["mir5-override-pipeline"]=pipeline}
            }}, log=function() end}
            setmetatable(env, {__index=_G})
            local chunk, message = loadfile(stage_path, "t", env)
            assert(chunk, message)
            return pcall(chunk)
          end

          function control_runtime(opponent)
            local markers, callbacks, events, saves = {}, {}, {}, 0
            local input, output, modules = {count=0}, {count=0}, {count=0}
            input.insert=function(row) input.count=input.count+row.count; return row.count end
            input.get_item_count=function(name) return name == "iron-plate" and input.count or 0 end
            output.get_item_count=function(name) return name == "iron-gear-wheel" and output.count or 0 end
            modules.insert=function(row) modules.count=modules.count+row.count; return row.count end
            modules.get_item_count=function(name) return name == "mir5-override-module" and modules.count or 0 end
            local machine={valid=true, energy=0}
            machine.set_recipe=function(name) assert(name == "mir5-override-ordinary"); machine.recipe=name; return true end
            machine.get_inventory=function(kind)
              if kind == 1 then return input end
              if kind == 2 then return output end
              error("unexpected inventory " .. tostring(kind))
            end
            machine.get_module_inventory=function() return modules end
            local recipe_effects={speed=true, productivity=true, consumption=true, pollution=true, quality=true}
            local category_map={speed=true, ["mir5-override-module-category"]=true}
            local env={
              script={active_mods={base="2.1.23", ["space-age"]="2.1.23", ["more-infinite-research"]="5.0.21000"},
                on_init=function(callback) callbacks.init=callback end,
                on_load=function(callback) callbacks.load=callback end,
                on_event=function(event, callback) events[event]=callback end},
              defines={events={on_tick=1}, inventory={crafter_input=1,crafter_output=2}},
              prototypes={module_category=category_map,
                recipe={
                  ["mir5-override-ordinary"]={maximum_productivity=1,allowed_effects=recipe_effects,allowed_module_categories=category_map},
                  ["mir5-override-recycling"]={maximum_productivity=.5,products={{type="item",name="iron-plate",amount=1,
                    independent_probability=opponent == "runtime-probability" and .3 or .2}}},
                  ["mir5-override-parameter"]={allowed_effects={speed=false,productivity=false,consumption=false,pollution=false,quality=false},allowed_module_categories={speed=true}}
                },
                entity={
                  ["mir5-override-assembler"]={allowed_effects=recipe_effects,allowed_module_categories=category_map,
                    energy_usage=opponent == "energy-unit" and 1 or 1 / 60,effect_receiver={}},
                  ["mir5-override-pipeline"]={effect_receiver={}}
                }},
              storage={},
            }
            env.game={tick=0, speed=1, forces={player={recipes={["mir5-override-ordinary"]={enabled=true}}}},
              surfaces={{create_entity=function(row) assert(row.name == "mir5-override-assembler"); return machine end}},
              server_save=function(name)
                assert(name == expected_complete_save, "completed save does not match native runner")
                saves=saves+1
              end}
            env.helpers={table_to_json=function(row) markers[#markers+1]=row; return "fixture-json" end}
            if opponent == "legacy-probability" then
              local product=env.prototypes.recipe["mir5-override-recycling"].products[1]
              product.independent_probability=nil; product.probability=.2
            end
            env.log=function() end
            env._G=env
            setmetatable(env,{__index=_G})
            local chunk, message=loadfile(control_path,"t",env); assert(chunk,message)
            local ok, result = pcall(chunk); assert(ok, result)
            return {env=env,callbacks=callbacks,events=events,input=input,output=output,modules=modules,
              machine=machine,markers=markers,saves=function() return saves end}
          end

          function selected_settings()
            local names = {
              ["mir-unrestricted-modules"]="bool-setting",
              ["mir-prototype-positive-power-floor"]="bool-setting",
              ["mir-pipeline-extent-multiplier"]="string-setting",
              ["mir-prototype-productivity-cap"]="string-setting",
              ["mir-productivity-cap-self-recycling-only"]="bool-setting",
              ["mir-recycling-return-chance"]="string-setting",
              ["mir-prototype-speed-floor"]="string-setting",
              ["mir-prototype-speed-cap"]="string-setting",
              ["mir-prototype-quality-cap"]="string-setting",
            }
            local raw = {["bool-setting"]={}, ["string-setting"]={}}
            for name, kind in pairs(names) do raw[kind][name]={setting_type="startup",default_value="original"} end
            local env={data={raw=raw}}; setmetatable(env,{__index=_G})
            local chunk, message=loadfile(settings_path,"t",env); assert(chunk,message)
            local ok, result=pcall(chunk); assert(ok,result)
            return raw
          end
        ''')

    def test_data_stage_accepts_exact_selected_nondefault_outputs(self):
        result = self.lua.globals().stage_fixture("pass")
        self.assertTrue(result[0] if isinstance(result, tuple) else result)

    def test_data_constructor_uses_f210_native_recipe_category_schema(self):
        self.lua.execute(r'''
          local function clone(value)
            if type(value) ~= "table" then return value end
            local result = {}
            for key, item in pairs(value) do result[key] = clone(item) end
            return result
          end
          local emitted = {}
          local env = {table={deepcopy=clone},data={raw={
            recipe={
              ["iron-gear-wheel"]={type="recipe", categories={"crafting"}},
              ["parameter-0"]={type="recipe", parameter=true},
            },
            module={["productivity-module-3"]={type="module"}},
            ["assembling-machine"]={
              ["assembling-machine-1"]={type="assembling-machine"},
              ["chemical-plant"]={type="assembling-machine",fluid_boxes={{},{}}},
            },
          }}}
          env.data.extend=function(_, rows)
            for _, row in ipairs(rows) do
              -- F210 removed both legacy recipe-category properties. This
              -- engine boundary rejects them even when a later oracle passes.
              if row.type == "recipe" then
                assert(row.category == nil and row.additional_categories == nil,
                  "F210 recipe must use categories, not removed category fields")
              end
              emitted[row.name] = row
            end
          end
          setmetatable(env,{__index=_G})
          assert(loadfile(data_path,"t",env))()
          local recycled=assert(emitted["mir5-override-recycling"])
          assert(#recycled.categories == 1 and recycled.categories[1] == "recycling")
          assert(recycled.maximum_productivity == .5)
          assert(recycled.results[1].probability == .25)
        ''')

    def test_data_stage_rejects_each_exact_native_only_witness_difference(self):
        for opponent in ("ordinary-cap", "recycling-field", "parameter", "receiver", "pipeline", "power"):
            with self.subTest(opponent=opponent):
                result = self.lua.globals().stage_fixture(opponent)
                self.assertFalse(result[0] if isinstance(result, tuple) else result)

    def test_settings_select_exact_interaction_without_a_profile_decoder(self):
        selected = self.lua.globals().selected_settings()
        self.assertTrue(selected["bool-setting"]["mir-unrestricted-modules"]["default_value"])
        self.assertTrue(selected["bool-setting"]["mir-prototype-positive-power-floor"]["default_value"])
        self.assertTrue(selected["bool-setting"]["mir-productivity-cap-self-recycling-only"]["default_value"])
        self.assertEqual("150", selected["string-setting"]["mir-pipeline-extent-multiplier"]["default_value"])
        self.assertEqual("percent-100", selected["string-setting"]["mir-prototype-productivity-cap"]["default_value"])
        self.assertEqual("percent-20", selected["string-setting"]["mir-recycling-return-chance"]["default_value"])
        self.assertEqual("saving-50", selected["string-setting"]["mir-prototype-speed-floor"]["default_value"])
        self.assertEqual("bonus-200", selected["string-setting"]["mir-prototype-speed-cap"]["default_value"])
        self.assertEqual("bonus-100", selected["string-setting"]["mir-prototype-quality-cap"]["default_value"])

    def test_control_registration_physical_witness_and_reload_are_bounded(self):
        runtime = self.lua.globals().control_runtime()
        runtime["callbacks"]["init"]()
        self.assertEqual("mir5-override-ordinary", runtime["machine"]["recipe"])
        self.assertEqual(10, runtime["input"]["count"])
        self.assertEqual(2, runtime["modules"]["count"])
        self.assertEqual(16, runtime["env"]["game"]["speed"])
        self.assertEqual("crafting", runtime["env"]["storage"]["mir5_override_interactions"]["phase"])
        self.assertEqual(0, runtime["saves"]())

        runtime["input"]["count"] = 0
        runtime["output"]["count"] = 6
        runtime["env"]["game"]["tick"] = 42
        runtime["events"][1]()
        state = runtime["env"]["storage"]["mir5_override_interactions"]
        self.assertEqual("complete", state["phase"])
        self.assertEqual(42, state["completed_tick"])
        self.assertEqual(1, runtime["saves"]())
        self.assertEqual("initial", runtime["markers"][1]["stage"])

        before = (state["phase"], state["completed_tick"], runtime["input"]["count"], runtime["output"]["count"])
        runtime["callbacks"]["load"]()
        self.assertEqual(before, (state["phase"], state["completed_tick"], runtime["input"]["count"], runtime["output"]["count"]))
        runtime["events"][1]()
        self.assertEqual("reload", runtime["markers"][2]["stage"])
        self.assertTrue(runtime["markers"][2]["witnesses"]["on_load_read_only"])
        self.assertEqual(1, runtime["saves"]())

    def test_control_rejects_watts_mistaken_for_runtime_joules_per_tick(self):
        runtime = self.lua.globals().control_runtime("energy-unit")
        with self.assertRaisesRegex(Exception, "runtime receiver witness differs"):
            runtime["callbacks"]["init"]()

    def test_control_rejects_old_or_changed_runtime_product_probability_without_repair(self):
        for opponent in ("legacy-probability", "runtime-probability"):
            with self.subTest(opponent=opponent):
                runtime = self.lua.globals().control_runtime(opponent)
                with self.assertRaisesRegex(Exception, "runtime recycling prototype differs"):
                    runtime["callbacks"]["init"]()
                diagnostic = runtime["markers"][1]
                self.assertEqual("failed", diagnostic["status"])
                self.assertEqual(0.2, diagnostic["expected"]["independent_probability"])
                actual = diagnostic["actual"]
                self.assertEqual(1, actual["product_count"])
                self.assertEqual(0.5, actual["maximum_productivity"])
                if opponent == "legacy-probability":
                    self.assertIsNone(actual["independent_probability"])
                    self.assertEqual(0.2, actual["legacy_probability"])
                else:
                    self.assertEqual(0.3, actual["independent_probability"])
                    product = runtime["env"]["prototypes"]["recipe"]["mir5-override-recycling"]["products"][1]
                    self.assertEqual(0.3, product["independent_probability"])
                self.assertEqual(0, runtime["saves"]())

    def test_f210_runtime_api_matches_only_the_public_witnesses(self):
        path = f210_runtime_api_path()
        if path is None:
            self.skipTest("F210 runtime-api.json is not installed")
        api = json.loads(path.read_text(encoding="utf-8"))
        classes = {row["name"]: row for row in api["classes"]}
        recipe_fields = {row["name"] for row in classes["LuaRecipePrototype"]["attributes"]}
        entity_fields = {row["name"] for row in classes["LuaEntityPrototype"]["attributes"]}
        self.assertTrue({"maximum_productivity", "products", "allowed_effects", "allowed_module_categories"} <= recipe_fields)
        self.assertTrue({"allowed_effects", "allowed_module_categories", "effect_receiver", "energy_usage"} <= entity_fields)
        self.assertNotIn("max_pipeline_extent", entity_fields)
        self.assertNotIn("independent_probability", recipe_fields)
        item_product = next(row for row in api["concepts"] if row["name"] == "ItemProduct")
        product_fields = {row["name"] for row in item_product["type"]["parameters"]}
        self.assertIn("independent_probability", product_fields)
        self.assertNotIn("probability", product_fields)

    def test_profile_binds_exact_current_official_closure_and_private_fixture(self):
        profile = json.loads(PROFILE.read_text(encoding="utf-8"))
        self.assertEqual("mir5-override-interactions-native-selection", profile["kind"])
        self.assertEqual("2.1.23", profile["engine"]["version"])
        mods = {row["name"]: row["version"] for row in profile["mods"] if row["enabled"]}
        for name in ("base", "elevated-rails", "quality", "recycler", "space-age"):
            self.assertEqual("2.1.23", mods[name])
        self.assertEqual("5.0.21000", mods["more-infinite-research"])
        self.assertEqual("0.1.0", mods["mir-fixture-mir5-override-interactions"])
        self.assertEqual("0.1.0", mods["mir-fixture-mir5-active-mods-observer"])
        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertIn("more-infinite-research = 5.0.21000", info["dependencies"])

    def test_fixture_keeps_engine_raw_acyclic_and_never_seeds_research_or_bonus(self):
        data = (FIXTURE / "data.lua").read_text(encoding="utf-8")
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        settings = (FIXTURE / "settings-updates.lua").read_text(encoding="utf-8")
        self.assertNotIn("setmetatable", data)
        self.assertNotIn("__index", data)
        for forbidden in ("add_research", ".researched", "productivity_bonus", "research_queue"):
            self.assertNotIn(forbidden, control)
        self.assertIn('"mir-prototype-productivity-cap"] = "percent-100"', settings)
        self.assertIn('"mir-recycling-return-chance"] = "percent-20"', settings)
        self.assertIn('"mir-productivity-cap-self-recycling-only"] = true', settings)
        self.assertIn("self-recycling-classifier=inactive", (FIXTURE / "data-final-fixes.lua").read_text(encoding="utf-8"))

    def test_data_stage_lua_sources_parse_without_an_engine_raw_cycle(self):
        for path in (self.lua.globals().data_path, self.lua.globals().settings_path, self.lua.globals().stage_path):
            self.assertTrue(self.lua.execute("return loadfile(...) ~= nil", path))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(OverrideInteractionsFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

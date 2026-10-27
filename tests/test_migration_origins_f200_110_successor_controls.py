"""Independent controls for the prepared direct MIR 1.1.0 successors."""
import argparse
from collections import Counter
import copy
import json
from pathlib import Path
import struct
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/migration-origins/f200-110-successor"
SOURCE_FIXTURE = ROOT / "tests/fixtures/migration-origins/f200-110-source"
F200_PROFILE = ROOT / "tests/profiles/migration-origins-1.1.0-successor-f200-2077.json"
F210_PROFILE = ROOT / "tests/profiles/migration-origins-1.1.0-successor-f210-2123.json"
LEGACY_MODULE_DEFINITIONS = ROOT / "source/research/legacy_module_credit_definitions.lua"
LEGACY_MODULE_RUNTIME = ROOT / "source/runtime/legacy_module_credits.lua"
DIRECT = "recipe-prod-research_gears-1"
ROBOT = "recipe-prod-research_robot_battery-1"
MODULES = "recipe-prod-research_modules-1"
RETIRED_SUCCESSOR_NAME = "mir-fixture-mir5-migration-origin-f200-110-successor"

# Pinned from the archived 1.1.0 config and F200 Base recipe output set; this
# test does not take its expected identities from the successor catalogue.
SOURCE_ROWS = {
    "recipe-prod-research_plastic-1", "recipe-prod-research_sulfur-1", "recipe-prod-research_batteries-1",
    "recipe-prod-research_explosives-1", DIRECT, "recipe-prod-research_iron_sticks-1",
    "recipe-prod-research_copper_cable-1", "recipe-prod-research_electronic_circuit-1",
    "recipe-prod-research_advanced_circuit-1", "recipe-prod-research_processing_unit-1",
    "recipe-prod-research_low_density_structure-1", "recipe-prod-research_rocket_fuel-1",
    "recipe-prod-research_copper-1", "recipe-prod-research_iron-1", "recipe-prod-research_engine-1",
    "recipe-prod-research_electric_engine-1", "recipe-prod-research_flying_robot_frame-1",
    MODULES, "recipe-prod-research_belts-1", "recipe-prod-research_inserters-1",
    "recipe-prod-research_bullets-1", "recipe-prod-research_rockets-1", ROBOT,
    "recipe-prod-research_science_pack_productivity-1", "recipe-prod-research_walls-1",
    "recipe-prod-research_grenades-1", "recipe-prod-research_rails-1",
    "recipe-prod-research_electric_energy-1", "recipe-prod-research_concrete-1",
    "recipe-prod-research_furnace-1", "recipe-prod-research_mining_drill-1",
}


def py(value):
    if hasattr(value, "items"):
        pairs = list(value.items())
        keys = [key for key, _ in pairs]
        if keys and all(isinstance(key, int) and key > 0 for key in keys) and set(keys) == set(range(1, len(keys) + 1)):
            return [py(value[index]) for index in range(1, len(keys) + 1)]
        return {key: py(item) for key, item in pairs}
    return value


def lua(runtime, value):
    if isinstance(value, dict):
        return runtime.table_from({key: lua(runtime, item) for key, item in value.items()})
    if isinstance(value, list):
        return runtime.table_from([lua(runtime, item) for item in value])
    return value


class MigrationOriginF200110SuccessorControls(unittest.TestCase):
    def candidate_raw(self):
        return {"technology": {
            DIRECT: {"type": "technology", "name": DIRECT, "level": 1, "upgrade": True,
                     "max_level": "infinite", "enabled": True,
                     "unit": {"count_formula": "9000*1.2^(L-1)", "time": 120,
                              "ingredients": [["automation-science-pack", 1]]},
                     "effects": [{"type": "change-recipe-productivity", "recipe": "iron-gear-wheel", "change": .10}]},
        }, "sentinel": {"unchanged": 43}}

    def run_data(self, raw, mods):
        catalogue_path = (FIXTURE / "catalogue.lua").as_posix()
        data_path = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.globals().catalogue_path = catalogue_path
        self.lua.globals().data_path = data_path
        self.lua.execute(r'''
          function migration_origin_110_successor_data(raw, mods)
            local env={data={raw=raw},mods=mods}
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue")
              return assert(loadfile(catalogue_path,"t",env))()
            end
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(data_path,"t",env))() end)
            return {ok=ok,message=tostring(message),raw=raw}
          end
        ''')
        return py(self.lua.eval("migration_origin_110_successor_data")(lua(self.lua, copy.deepcopy(raw)), lua(self.lua, mods)))

    def test_catalogue_pins_all_31_old_rows_and_the_separate_worker_battery_fact(self):
        catalogue_path = (FIXTURE / "catalogue.lua").as_posix()
        self.lua.globals().catalogue_path = catalogue_path
        self.lua.execute("function migration_origin_110_successor_catalogue() return assert(loadfile(catalogue_path))() end")
        catalogue = py(self.lua.eval("migration_origin_110_successor_catalogue")())
        rows = catalogue["rows"]
        self.assertEqual(SOURCE_ROWS, set(rows))
        self.assertEqual(31, len(rows))
        self.assertEqual("mir-fixture-mir5-migration-origin-f200-110-source", catalogue["fixture"])
        self.assertEqual(("change-recipe-productivity", "iron-gear-wheel", .10),
                         (rows[DIRECT][0]["type"], rows[DIRECT][0]["recipe"], rows[DIRECT][0]["change"]))
        self.assertEqual(("worker-robot-battery", .10), (rows[ROBOT][0]["type"], rows[ROBOT][0]["modifier"]))
        self.assertEqual(75, sum(len(effects) for effects in rows.values()))
        self.assertEqual(
            Counter({
                ("change-recipe-productivity", "speed-module", .10): 1,
                ("change-recipe-productivity", "productivity-module", .10): 1,
                ("change-recipe-productivity", "efficiency-module", .10): 1,
                ("change-recipe-productivity", "speed-module", .01): 1,
                ("change-recipe-productivity", "productivity-module", .01): 1,
                ("change-recipe-productivity", "efficiency-module", .01): 1,
                ("change-recipe-productivity", "speed-module-2", .05): 1,
                ("change-recipe-productivity", "productivity-module-2", .05): 1,
                ("change-recipe-productivity", "efficiency-module-2", .05): 1,
                ("change-recipe-productivity", "speed-module-3", .02): 1,
                ("change-recipe-productivity", "productivity-module-3", .02): 1,
                ("change-recipe-productivity", "efficiency-module-3", .02): 1,
            }),
            Counter((effect["type"], effect.get("recipe"), effect.get("change")) for effect in rows[MODULES]),
        )
        single_precision_one_percent = struct.unpack("<f", struct.pack("<f", .01))[0]
        self.assertEqual(format(single_precision_one_percent, ".17g"), catalogue["source_change_tokens"][.01])
        self.assertEqual("0.1", catalogue["source_modifier_tokens"][.10])
        for recipe in ("speed-module", "productivity-module", "efficiency-module"):
            with self.subTest(recipe=recipe):
                self.assertAlmostEqual(.11, sum(effect["change"] for effect in rows[MODULES]
                                                 if effect.get("recipe") == recipe))
        self.assertNotIn("recipe-prod-research_inventory_capacity-1", rows)
        self.assertEqual(42, len(catalogue["settings"]))
        self.assertTrue(catalogue["settings"]["ips-enable-research_breeding"])
        self.assertFalse(catalogue["settings"]["ips-enable-research_inventory_capacity"])
        module_credit = catalogue["module_credit"]
        self.assertEqual(
            Counter({
                ("change-recipe-productivity", "speed-module", .10): 1,
                ("change-recipe-productivity", "productivity-module", .10): 1,
                ("change-recipe-productivity", "efficiency-module", .10): 1,
                ("change-recipe-productivity", "speed-module-2", .05): 1,
                ("change-recipe-productivity", "productivity-module-2", .05): 1,
                ("change-recipe-productivity", "efficiency-module-2", .05): 1,
                ("change-recipe-productivity", "speed-module-3", .02): 1,
                ("change-recipe-productivity", "productivity-module-3", .02): 1,
                ("change-recipe-productivity", "efficiency-module-3", .02): 1,
            }),
            Counter((effect["type"], effect["recipe"], effect["change"]) for effect in module_credit["public"]),
        )
        self.assertEqual(
            [("mir-legacy-module-credit-speed-module", "speed-module", .01),
             ("mir-legacy-module-credit-productivity-module", "productivity-module", .01),
             ("mir-legacy-module-credit-efficiency-module", "efficiency-module", .01)],
            [(holder["id"], holder["recipe"], holder["change"]) for holder in module_credit["holders"]],
        )

    def test_successor_wrappers_retain_the_source_fixture_identity_and_only_change_the_targeted_wrapper_version(self):
        source = json.loads((SOURCE_FIXTURE / "info.json").read_text(encoding="utf-8"))
        f200 = json.loads((FIXTURE / "info-f200.json").read_text(encoding="utf-8"))
        f210 = json.loads((FIXTURE / "info-f210.json").read_text(encoding="utf-8"))
        source_version = tuple(map(int, source["version"].split(".")))
        for wrapper, base, mir, version in (
            (f200, "2.0", "5.0.20000", "0.2.0"),
            (f210, "2.1", "5.0.21000", "0.3.0"),
        ):
            with self.subTest(version=version):
                self.assertEqual(source["name"], wrapper["name"])
                self.assertEqual(version, wrapper["version"])
                self.assertEqual(base, wrapper["factorio_version"])
                self.assertIn(f"more-infinite-research = {mir}", wrapper["dependencies"])
                self.assertNotEqual(RETIRED_SUCCESSOR_NAME, wrapper["name"])
                self.assertGreater(tuple(map(int, wrapper["version"].split("."))), source_version)

    def test_data_guard_admits_only_the_two_exact_candidate_targets_and_accelerates_only_direct_cost(self):
        f200 = {"base": "2.0.77", "more-infinite-research": "5.0.20000",
                "mir-fixture-mir5-active-mods-observer": "0.1.0",
                "mir-fixture-mir5-migration-origin-f200-110-source": "0.2.0"}
        f210 = {"base": "2.1.23", "more-infinite-research": "5.0.21000",
                "mir-fixture-mir5-active-mods-observer": "0.1.0",
                "mir-fixture-mir5-migration-origin-f200-110-source": "0.3.0"}
        for label, mods in (("f200", f200), ("f210", f210)):
            with self.subTest(label=label):
                accepted = self.run_data(self.candidate_raw(), mods)
                self.assertTrue(accepted["ok"], accepted["message"])
                unit = accepted["raw"]["technology"][DIRECT]["unit"]
                self.assertEqual((1, None, 1), (unit.get("count"), unit.get("count_formula"), unit["time"]))
                self.assertEqual(43, accepted["raw"]["sentinel"]["unchanged"])
        variants = []
        wrong_target = dict(f200); wrong_target["base"] = "2.1.23"; variants.append(("target", self.candidate_raw(), wrong_target))
        missing_observer = dict(f200); missing_observer.pop("mir-fixture-mir5-active-mods-observer"); variants.append(("observer", self.candidate_raw(), missing_observer))
        wrong_effect = self.candidate_raw(); wrong_effect["technology"][DIRECT]["effects"][0]["change"] = .05; variants.append(("effect", wrong_effect, f200))
        empty_science = self.candidate_raw(); empty_science["technology"][DIRECT]["unit"]["ingredients"] = []; variants.append(("science", empty_science, f200))
        for label, raw, mods in variants:
            with self.subTest(label=label):
                before = copy.deepcopy(raw)
                rejected = self.run_data(raw, mods)
                self.assertFalse(rejected["ok"])
                # lupa represents an empty Lua vector as an empty mapping on
                # the way back to Python.  Check the actual mutation boundary
                # instead: rejection cannot alter the selected cost/time or
                # unrelated raw table, including the malformed empty science
                # vector that triggered this opponent.
                before_direct = before["technology"][DIRECT]
                after_direct = rejected["raw"]["technology"][DIRECT]
                self.assertEqual(before_direct["unit"].get("count"), after_direct["unit"].get("count"))
                self.assertEqual(before_direct["unit"].get("count_formula"), after_direct["unit"].get("count_formula"))
                self.assertEqual(before_direct["unit"].get("time"), after_direct["unit"].get("time"))
                self.assertEqual(before["sentinel"], rejected["raw"]["sentinel"])

    def test_control_registers_without_runtime_access_and_refuses_missing_source_before_candidate_writes(self):
        path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().successor_control_path = path
        self.lua.execute(r'''
          function migration_origin_110_successor_control()
            local callbacks,forbidden={events={}},{ }
            local env={script={active_mods={base="2.0.77",["more-infinite-research"]="5.0.20000",
                ["mir-fixture-mir5-active-mods-observer"]="0.1.0",
                ["mir-fixture-mir5-migration-origin-f200-110-source"]="0.2.0"},
              on_configuration_changed=function(fn) callbacks.configuration=fn end,
              on_load=function(fn) callbacks.load=fn end,on_event=function(event,fn) callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}},storage={}}
            env.require=function(name) assert(name=="__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue")
              return {storage_key="mir5_migration_origin_f200_110_source",fixture="mir-fixture-mir5-migration-origin-f200-110-source",
                direct="recipe-prod-research_gears-1",gear_recipe="iron-gear-wheel",save="mir5-native-complete",deadline_ticks=18000,lab_packs=32,expected_gear_delta=.1,
                source_change_tokens={[.1]="0.10000000149011612",[.05]="0.05000000074505806",[.02]="0.019999999552965164",[.2]="0.20000000298023224"},
                source_modifier_tokens={[.1]="0.1"},
                rows={["recipe-prod-research_gears-1"]={{type="change-recipe-productivity",recipe="iron-gear-wheel",change=.1}}},settings={test=true},
                targets={f200={base="2.0.77",mir="5.0.20000",fixture="0.2.0"},f210={base="2.1.23",mir="5.0.21000",fixture="0.3.0"}}}
            end
            env._G=env;setmetatable(env,{__index=function(_,key)
              if key=="game" or key=="settings" then forbidden[key]=true;return nil end
              return _G[key]
            end})
            local ok_parse,message_parse=pcall(function() assert(loadfile(successor_control_path,"t",env))() end)
            local ok_config,message_config=pcall(function() callbacks.configuration({}) end)
            return {ok_parse=ok_parse,message_parse=tostring(message_parse),ok_config=ok_config,message_config=tostring(message_config),callbacks=callbacks,forbidden=forbidden,storage=env.storage}
          end
        ''')
        result = py(self.lua.eval("migration_origin_110_successor_control")())
        self.assertTrue(result["ok_parse"], result["message_parse"])
        self.assertIsNotNone(result["callbacks"]["configuration"])
        self.assertIsNotNone(result["callbacks"]["load"])
        self.assertEqual({}, result["forbidden"])
        self.assertFalse(result["ok_config"])
        self.assertIn("protected MIR 1.1 source state is absent", result["message_config"])
        self.assertEqual({}, result["storage"])

    def test_profiles_bind_the_one_passed_r05_source_and_the_coherent_module_credit_candidate(self):
        f200, f210 = json.loads(F200_PROFILE.read_text()), json.loads(F210_PROFILE.read_text())
        for profile in (f200, f210):
            self.assertEqual("88FC8E9891040275E001930C3E6AA0A4A7A28C31D81DF30E3F08AEDD98E5019A",
                             profile["source_save"]["sha256"])
            self.assertEqual("4FBD622144E3B69E39C0530385AA70C92971208584CA32D4A10B1FCC1A978997",
                             profile["source_save"]["source_result_sha256"])
            self.assertEqual(("c74b7c4680545f3ccf27f38016d1144fefe8eee3", "f81c63afca2e6eb5b7e46dffe892548553899db3"),
                             (profile["candidate"]["source_commit"], profile["candidate"]["player_tree"]))
            self.assertEqual("bec37fb87a05d17cf4cf0225e0458218830fef63", profile["source_fixture_commit"])
            self.assertEqual("3ae2711867cd60f6c871f641c331349d941dd8c3", profile["source_fixture_controller_commit"])
            self.assertEqual("c03257d1a672ca62ff523afae65df3239bef518c", profile["successor_fixture_commit"])
            self.assertEqual("2fb64822b82569e3b50f0653e361fb7148f18b63", profile["origin_source_commit"])
        self.assertEqual("1767DE15AB78628C4C404D280F4DC789521BF4DEE86B349ED379C47234BD69F0",
                         f200["archive_sha256"]["mir-fixture-mir5-migration-origin-f200-110-source_0.2.0.zip"])
        self.assertEqual("E1878CAEE523CDC4DC86C9E6B0B5029A78E4D96ADC1A3C80BE8521355A6655A3",
                         f210["archive_sha256"]["mir-fixture-mir5-migration-origin-f200-110-source_0.3.0.zip"])
        self.assertEqual("050AC35BAB6BA1F01E160DB612B73A03E58E0ABE6A291D18109FAB1B235B63B5",
                         f200["archive_sha256"]["more-infinite-research_5.0.20000.zip"])
        self.assertEqual("625756F9E2536383954A121EB24FFB3AE0C0A540B7557E3F03A79C2D8A6A0D59",
                         f210["archive_sha256"]["more-infinite-research_5.0.21000.zip"])
        self.assertNotIn("space-age", {entry["name"] for entry in f210["mods"]})

    def test_profiles_reject_the_r12_stale_fixture_archive_pins(self):
        cases = (
            (json.loads(F200_PROFILE.read_text()),
             "mir-fixture-mir5-migration-origin-f200-110-source_0.2.0.zip",
             "1767DE15AB78628C4C404D280F4DC789521BF4DEE86B349ED379C47234BD69F0",
             "29F2597180F0BCB8CB25A651A19068678635D42C35A96EE56F6186DE737037E0"),
            (json.loads(F210_PROFILE.read_text()),
             "mir-fixture-mir5-migration-origin-f200-110-source_0.3.0.zip",
             "E1878CAEE523CDC4DC86C9E6B0B5029A78E4D96ADC1A3C80BE8521355A6655A3",
             "F4C54047A9734180D31C14F18BE38B744F053F399A0D8184961C2B563463C831"),
        )

        def assert_approved(profile, archive, approved):
            self.assertEqual(approved, profile["archive_sha256"][archive])

        for profile, archive, approved, stale in cases:
            with self.subTest(archive=archive):
                assert_approved(profile, archive, approved)
                rejected = copy.deepcopy(profile)
                rejected["archive_sha256"][archive] = stale
                with self.assertRaises(AssertionError):
                    assert_approved(rejected, archive, approved)

    def test_control_keeps_only_the_saved_source_roster_as_earned_state(self):
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn("assert_snapshot(value.player_snapshot, names, \"player\", 2, 0)", control)
        self.assertIn("assert_snapshot(value.foreign_snapshot, names, \"foreign\", 1, nil)", control)
        self.assertIn("assert_snapshot(value.detached_snapshot, names, \"detached\", 1, .27)", control)
        self.assertIn("worker-robot-battery contribution", control)
        self.assertIn("event.by_script ~= false", control)
        self.assertLess(control.index("assert_source_before(state_value, names, false, 0)"), control.index("state_value.successors ="))
        self.assertLess(control.index("observe_module_bonuses(force, snapshot, label)"),
                        control.index("for recipe, expected in pairs(snapshot.recipes) do"))
        initial_reset = "complete(target, state_value, successor)\n    reset_after_candidate_lab(target, state_value, successor)"
        self.assertIn(initial_reset, control)
        self.assertLess(control.index(initial_reset),
                        control.index("game.server_save(catalogue.save)"))
        self.assertNotIn("manual_mining_speed_modifier =", control)
        self.assertNotIn("pairs(game.forces.player.technologies)", control)

    def _install_lifecycle_model(self):
        """Install the source-storage-aware fixture lifecycle double."""
        catalogue_path = (FIXTURE / "catalogue.lua").as_posix()
        control_path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().catalogue_path = catalogue_path
        self.lua.globals().successor_control_path = control_path
        self.lua.globals().legacy_module_definitions_path = LEGACY_MODULE_DEFINITIONS.as_posix()
        self.lua.globals().legacy_module_runtime_path = LEGACY_MODULE_RUNTIME.as_posix()
        self.lua.execute(r'''
          function migration_origin_110_successor_lifecycle(target, source_fixture_name, active_wrapper_name, catalogue_fixture_name, legacy_module_bonus, reset_drops_module_bonus, saved_battery_token, current_recipe_scalar, duplicate_current_recipe, foreign_saved, foreign_queue_progress, foreign_current_saved, foreign_current_technology, recipe_snapshot_variant)
            local callbacks={events={}}
            local env={storage={},logs={},created_labs=0,saved=false,
              script={active_mods={},on_configuration_changed=function(fn) callbacks.configuration=fn end,
                on_load=function(fn) callbacks.load=fn end,on_event=function(event,fn) callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}}
            local catalogue
            env.require=function(name)
              if name=="__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue" then
                if catalogue==nil then
                  catalogue=assert(loadfile(catalogue_path,"t",env))()
                  if catalogue_fixture_name~=nil then catalogue.fixture=catalogue_fixture_name end
                end
                return catalogue
              end
              if name=="research.legacy_module_credit_definitions" then
                return assert(loadfile(legacy_module_definitions_path,"t",env))()
              end
              if name=="runtime.legacy_module_credits" then
                return assert(loadfile(legacy_module_runtime_path,"t",env))()
              end
              if name=="platform.target" then
                if target=="f200" then return {id="f200",recipe_productivity=true,distribution_version="5.0.20000"} end
                return {id="f210",recipe_productivity=true,distribution_version="5.0.21000"}
              end
              error("unexpected module: "..tostring(name))
            end
            env.log=function(message) env.logs[#env.logs+1]=message end
            env._G=env;setmetatable(env,{__index=_G})
            catalogue=env.require("__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue")
            local UINT32_MAX=4294967295
            local function close(left,right) return type(left)=="number" and type(right)=="number" and math.abs(left-right)<=.000001 end
            local function names()
              local result={};for name in pairs(catalogue.rows) do result[#result+1]=name end;table.sort(result);return result
            end
            local roster=names()
            local function source_effect_signature(name)
              local rows={}
              for _,effect in ipairs(catalogue.rows[name]) do
                if effect.type=="change-recipe-productivity" then
                  rows[#rows+1]=effect.type.."|"..effect.recipe.."|"..catalogue.source_change_tokens[effect.change]
                elseif effect.type=="worker-robot-battery" then
                  rows[#rows+1]=effect.type.."|"..catalogue.source_modifier_tokens[effect.modifier]
                end
              end
              table.sort(rows);return table.concat(rows,",")
            end
            local function recipe_values(direct_earned)
              local result={}
              for name,effects in pairs(catalogue.rows) do
                for _,effect in ipairs(effects) do
                  if effect.type=="change-recipe-productivity" then
                    if name==catalogue.direct and not direct_earned then
                      result[effect.recipe]=result[effect.recipe] or 0
                    else
                      result[effect.recipe]=(result[effect.recipe] or 0)+effect.change
                    end
                  end
                end
              end
              return result
            end
            local function source_snapshot(direct_level,direct_saved)
              local technologies,effects={},{}
              for _,name in ipairs(roster) do
                technologies[name]={level=name==catalogue.direct and direct_level or 2,researched=false,
                  enabled=true,visible=false,saved=name==catalogue.direct and direct_saved or 0,maximum=UINT32_MAX}
                effects[name]=source_effect_signature(name)
              end
              return {technologies=technologies,effects=effects,recipes=recipe_values(direct_level>=2),
                fields={manual_mining_speed_modifier=0,worker_robots_battery_modifier=.1}}
            end
            local function copy_effects(effects)
              local out={}
              for index,effect in ipairs(effects) do
                out[index]={type=effect.type,recipe=effect.recipe,change=effect.change}
              end
              return out
            end
            local function install_current_module_credit(force,snapshot,definitions)
              local main=force.technologies["recipe-prod-research_modules-1"]
              main.prototype={name="recipe-prod-research_modules-1",level=1,max_level=UINT32_MAX,
                hidden=false,enabled=true,upgrade=true,effects=copy_effects(catalogue.module_credit.public)}
              for _,row in ipairs(definitions.technologies()) do
                force.technologies[row.name]={valid=true,name=row.name,level=1,researched=false,enabled=false,visible_when_disabled=false,
                  research_unit_count=row.unit.count,research_unit_energy=row.unit.time*60,
                  research_unit_ingredients={{name=row.unit.ingredients[1][1],amount=row.unit.ingredients[1][2]}},
                  prototype={name=row.name,level=row.level,max_level=UINT32_MAX,hidden=row.hidden,enabled=row.enabled,
                    visible_when_disabled=row.visible_when_disabled,upgrade=row.upgrade,effects=copy_effects(row.effects)}}
              end
            end
            local order={}
            local function make_force(label,index,direct_level,direct_saved)
              local snapshot=source_snapshot(direct_level,direct_saved)
              local force={name=label,index=index,valid=true,technologies={},recipes={},manual_mining_speed_modifier=0,
                worker_robots_battery_modifier=.1,research_queue={},research_progress=0,current_research=nil,add_calls=0,reset_calls=0}
              for _,name in ipairs(roster) do
                local saved=snapshot.technologies[name]
                local value={name=name,valid=true,level=saved.level,researched=false,enabled=true,visible_when_disabled=false,
                  saved_progress=saved.saved,prototype={max_level=UINT32_MAX,effects=catalogue.rows[name]},
                  research_unit_ingredients={{name="automation-science-pack",amount=1}}}
                value.force=force;force.technologies[name]=value
              end
              for recipe,value in pairs(snapshot.recipes) do force.recipes[recipe]={valid=true,productivity_bonus=value} end
              -- Native recipes exist independently of whether this force has
              -- earned a source productivity contribution for them.
              if force.recipes[catalogue.gear_recipe]==nil then
                force.recipes[catalogue.gear_recipe]={valid=true,productivity_bonus=0}
              end
              force.add_research=function(research)
                force.add_calls=force.add_calls+1;force.current_research=research;force.research_queue={research};force.research_progress=0;return true
              end
              force.reset_technology_effects=function()
                force.reset_calls=force.reset_calls+1;order[#order+1]="reset:"..label
                if force.reset_drops_module_bonus then
                  for _,recipe in ipairs({"speed-module","productivity-module","efficiency-module"}) do
                    force.recipes[recipe].productivity_bonus=force.recipes[recipe].productivity_bonus-.01
                  end
                end
              end
              return force,snapshot
            end
            local player,player_snapshot=make_force("player",1,2,0)
            if foreign_saved==nil then foreign_saved=0 end
            if foreign_queue_progress==nil then foreign_queue_progress=.42 end
            local foreign,foreign_snapshot=make_force("foreign",2,1,foreign_saved)
            local detached,detached_snapshot=make_force("detached",3,1,.27)
            player.reset_drops_module_bonus=reset_drops_module_bonus==true
            foreign.current_research=foreign.technologies[catalogue.direct]
            foreign.research_queue={foreign.technologies[catalogue.direct],foreign.technologies["recipe-prod-research_plastic-1"]}
            foreign.research_progress=foreign_queue_progress
            if foreign_current_technology~=nil then
              foreign.technologies[catalogue.direct]=foreign_current_technology
            elseif foreign_current_saved~=nil then
              foreign.technologies[catalogue.direct].saved_progress=foreign_current_saved
            end
            local state={phase="completed",roster=roster,source_labs=1,player_snapshot=player_snapshot,
              foreign_index=2,foreign_snapshot=foreign_snapshot,
              foreign_queue={current=catalogue.direct,queue={catalogue.direct,"recipe-prod-research_plastic-1"},progress=.42},
              detached_index=3,detached_snapshot=detached_snapshot}
            local recipe_snapshot, recipe_variant = foreign_snapshot, recipe_snapshot_variant
            if type(recipe_variant)=="string" and recipe_variant:sub(1,9)=="detached-" then
              recipe_snapshot,recipe_variant=detached_snapshot,recipe_variant:sub(10)
            end
            if recipe_variant=="missing-direct" then
              recipe_snapshot.recipes[catalogue.gear_recipe]=nil
            elseif recipe_variant=="extra" then
              recipe_snapshot.recipes["fixture-extra-recipe"]=0
            elseif recipe_variant=="wrong-direct" then
              recipe_snapshot.recipes[catalogue.gear_recipe]=.1
            elseif recipe_variant~=nil then
              error("unexpected source recipe variant: "..tostring(recipe_snapshot_variant))
            end
            if saved_battery_token~=nil then
              state.player_snapshot.effects[catalogue.robot_battery]="worker-robot-battery|"..saved_battery_token
            end
            -- Model Factorio's per-mod storage ownership: the protected
            -- state belongs to the source fixture identity, not every
            -- fixture whose source directory happens to contain this control.
            local storage_by_mod={[source_fixture_name]={[catalogue.storage_key]=state}}
            if storage_by_mod[active_wrapper_name]==nil then storage_by_mod[active_wrapper_name]={} end
            env.storage=storage_by_mod[active_wrapper_name]
            if legacy_module_bonus~=nil then
              for _,recipe in ipairs({"speed-module","productivity-module","efficiency-module"}) do
                player.recipes[recipe].productivity_bonus=legacy_module_bonus
              end
            end
            env.settings={startup={}}
            for name,value in pairs(catalogue.settings) do env.settings.startup[name]={value=value} end
            local inventory={items={}}
            inventory.clear=function() inventory.items={} end
            inventory.insert=function(row) inventory.items[row.name]=(inventory.items[row.name] or 0)+row.count;return row.count end
            inventory.get_item_count=function(name) return inventory.items[name] or 0 end
            local entity={valid=true,energy=0,get_inventory=function(_) return inventory end}
            env.game={forces={player=player,[2]=foreign,[3]=detached},tick=0,
              surfaces={[1]={create_entity=function(_) env.created_labs=env.created_labs+1;return entity end}},
              server_save=function(_) env.saved=true;order[#order+1]="save" end}
            if target=="f200" then
              env.script.active_mods={base="2.0.77",["more-infinite-research"]="5.0.20000",
                [active_wrapper_name]="0.2.0",["mir-fixture-mir5-active-mods-observer"]="0.1.0"}
            else
              env.script.active_mods={base="2.1.23",["more-infinite-research"]="5.0.21000",
                [active_wrapper_name]="0.3.0",["mir-fixture-mir5-active-mods-observer"]="0.1.0"}
            end
            local definitions=env.require("research.legacy_module_credit_definitions")
            install_current_module_credit(player,player_snapshot,definitions)
            install_current_module_credit(foreign,foreign_snapshot,definitions)
            install_current_module_credit(detached,detached_snapshot,definitions)
            local module_runtime=env.require("runtime.legacy_module_credits")
            assert(module_runtime.on_configuration_changed({mod_changes={
              ["more-infinite-research"]={old_version="1.1.0",new_version=env.script.active_mods["more-infinite-research"]}}})==true)
            local function alter_current_module_shape(force)
              local effects=force.technologies["recipe-prod-research_modules-1"].prototype.effects
              if current_recipe_scalar~=nil then
                for _,effect in ipairs(effects) do
                  if effect.change==.1 then effect.change=current_recipe_scalar end
                end
              end
              if duplicate_current_recipe then
                effects[#effects+1]={type="change-recipe-productivity",recipe="speed-module",change=current_recipe_scalar or .1}
              end
            end
            alter_current_module_shape(player);alter_current_module_shape(foreign);alter_current_module_shape(detached)
            local marker_counts={}
            local function marker_count()
              local count=0
              for _,value in ipairs(env.logs) do
                if value:sub(1,29)=="[MIR5_NATIVE_FIXTURE] RESULT " then count=count+1 end
              end
              return count
            end
            local ok,message=pcall(function()
              assert(loadfile(successor_control_path,"t",env))()
              callbacks.configuration({})
              local direct=player.technologies[catalogue.direct]
              inventory.items["automation-science-pack"]=0
              direct.level=direct.level+1
              player.recipes[catalogue.gear_recipe].productivity_bonus=player.recipes[catalogue.gear_recipe].productivity_bonus+catalogue.expected_gear_delta
              player.current_research=nil;player.research_queue={};callbacks.events[1]({research=direct,by_script=false})
              env.game.tick=1;callbacks.events[2]()
              local saved_phase=state.successors[target].phase
              callbacks.load();env.game.tick=2;callbacks.events[2]()
               marker_counts.after_first_reload=marker_count()
               env.game.tick=3;callbacks.events[2]()
               marker_counts.after_ordinary_tick=marker_count()
               callbacks.load();env.game.tick=4;callbacks.events[2]()
               marker_counts.after_second_reload=marker_count()
              assert(saved_phase=="completed")
            end)
            return {ok=ok,message=tostring(message),state=state,
              saved=env.saved,created_labs=env.created_labs,logs=env.logs,
              foreign_gear=foreign.recipes[catalogue.gear_recipe].productivity_bonus,
              detached_gear=detached.recipes[catalogue.gear_recipe].productivity_bonus,
              player_gear=player.recipes[catalogue.gear_recipe].productivity_bonus,
              player_level=player.technologies[catalogue.direct].level,
              player_manual=player.manual_mining_speed_modifier,player_battery=player.worker_robots_battery_modifier,
               foreign_progress=foreign.research_progress,foreign_saved=foreign.technologies[catalogue.direct].saved_progress,
               detached_progress=detached.technologies[catalogue.direct].saved_progress,
               player_add_calls=player.add_calls,player_reset_calls=player.reset_calls,
               foreign_reset_calls=foreign.reset_calls,detached_reset_calls=detached.reset_calls,order=order,
               marker_counts=marker_counts,
               source_state_changed=state.successors~=nil,
              source_battery_effect=state.player_snapshot.effects[catalogue.robot_battery],
              candidate_module_effects=#player.technologies["recipe-prod-research_modules-1"].prototype.effects,
              player_module_holders={player.technologies[catalogue.module_credit.holders[1].id].level,
                player.technologies[catalogue.module_credit.holders[2].id].level,
                player.technologies[catalogue.module_credit.holders[3].id].level},
              foreign_module_holders={foreign.technologies[catalogue.module_credit.holders[1].id].level,
                foreign.technologies[catalogue.module_credit.holders[2].id].level,
                foreign.technologies[catalogue.module_credit.holders[3].id].level},
              detached_module_holders={detached.technologies[catalogue.module_credit.holders[1].id].level,
                detached.technologies[catalogue.module_credit.holders[2].id].level,
                detached.technologies[catalogue.module_credit.holders[3].id].level},
              active_state_changed=type(storage_by_mod[active_wrapper_name][catalogue.storage_key])=="table"
                and storage_by_mod[active_wrapper_name][catalogue.storage_key].successors~=nil}
          end
        ''')
    def test_control_preserves_the_independent_source_snapshot_through_one_real_candidate_lab_and_reload(self):
        """Exercise the real fixture lifecycle, including the non-earned direct row.

        The saved player owns the first direct gear contribution (level two),
        whereas the foreign and detached source witnesses keep that technology
        at level one.  Their gear bonus must therefore remain zero.  This is a
        source-state fact, not a convenience projection of the current MIR5
        catalogue.
        """
        self._install_lifecycle_model()
        source = json.loads((SOURCE_FIXTURE / "info.json").read_text(encoding="utf-8"))
        wrappers = {
            "f200": json.loads((FIXTURE / "info-f200.json").read_text(encoding="utf-8")),
            "f210": json.loads((FIXTURE / "info-f210.json").read_text(encoding="utf-8")),
        }
        for target, wrapper in wrappers.items():
            with self.subTest(target=target):
                result = py(self.lua.eval("migration_origin_110_successor_lifecycle")(
                    target, source["name"], wrapper["name"]))
                self.assertTrue(result["ok"], result["message"])
                self.assertTrue(result["saved"])
                self.assertEqual(1, result["created_labs"])
                self.assertEqual(1, result["player_add_calls"])
                self.assertEqual((3, .2), (result["player_level"], result["player_gear"]))
                self.assertEqual((0, 0), (result["foreign_gear"], result["detached_gear"]))
                self.assertEqual((0, .1), (result["player_manual"], result["player_battery"]))
                self.assertEqual((.42, .27), (result["foreign_progress"], result["detached_progress"]))
                self.assertEqual(0, result["foreign_saved"])
                self.assertEqual((1, 0, 0), (result["player_reset_calls"], result["foreign_reset_calls"], result["detached_reset_calls"]))
                self.assertEqual(["reset:player", "save"], result["order"])
                self.assertEqual(9, result["candidate_module_effects"])
                self.assertEqual(([2, 2, 2], [2, 2, 2], [2, 2, 2]),
                                 (result["player_module_holders"], result["foreign_module_holders"], result["detached_module_holders"]))
                self.assertEqual("completed", result["state"]["successors"][target]["phase"])
                self.assertEqual(1, result["state"]["successors"][target]["candidate_actual_labs"])
                observations = [json.loads(value.split(" OBSERVED ", 1)[1]) for value in result["logs"]
                                if value.startswith("[MIR5_NATIVE_FIXTURE] OBSERVED ")]
                markers = [value for value in result["logs"] if value.startswith("[MIR5_NATIVE_FIXTURE] RESULT ")]
                self.assertGreaterEqual(len(observations), 3)
                self.assertTrue(any((.11, .11, .11) ==
                                    (value["original_source_speed_module_bonus"],
                                     value["original_source_productivity_module_bonus"],
                                     value["original_source_efficiency_module_bonus"])
                                    for value in observations))
                self.assertTrue(any((.11, .11, .11) ==
                                    (value["current_candidate_speed_module_bonus"],
                                     value["current_candidate_productivity_module_bonus"],
                                     value["current_candidate_efficiency_module_bonus"])
                                    for value in observations))
                self.assertEqual(3, len(markers))
                self.assertIn('"stage":"initial"', markers[0])
                self.assertIn('"stage":"reload"', markers[1])
                self.assertIn('"stage":"reload"', markers[2])
                self.assertEqual({"after_first_reload": 2, "after_ordinary_tick": 2, "after_second_reload": 3},
                                 result["marker_counts"])
                self.assertTrue(result["source_state_changed"])
                self.assertTrue(result["active_state_changed"])

    def test_control_keeps_foreign_saved_progress_independent_of_active_queue_progress(self):
        self._install_lifecycle_model()
        source = json.loads((SOURCE_FIXTURE / "info.json").read_text(encoding="utf-8"))
        wrapper = json.loads((FIXTURE / "info-f200.json").read_text(encoding="utf-8"))
        accepted = py(self.lua.eval("migration_origin_110_successor_lifecycle")(
            "f200", source["name"], wrapper["name"], None, None, False, None, None, False, 0, .42, None))
        self.assertTrue(accepted["ok"], accepted["message"])
        self.assertEqual((0, .42), (accepted["foreign_saved"], accepted["foreign_progress"]))
        self.assertEqual((1, 1), (accepted["created_labs"], accepted["player_add_calls"]))

        saved_fraction = py(self.lua.eval("migration_origin_110_successor_lifecycle")(
            "f200", source["name"], wrapper["name"], None, None, False, None, None, False, .125, .42, None))
        self.assertTrue(saved_fraction["ok"], saved_fraction["message"])
        self.assertEqual((.125, .42), (saved_fraction["foreign_saved"], saved_fraction["foreign_progress"]))
        self.assertEqual((1, 1), (saved_fraction["created_labs"], saved_fraction["player_add_calls"]))

        opponents = (
            ("saved", .125, .42, .1,
             "foreign retained source technology differs: recipe-prod-research_gears-1"),
            ("queue", .125, .41, None, "foreign queue/progress differs"),
        )
        for label, saved, progress, current_saved, expected in opponents:
            with self.subTest(label=label):
                result = py(self.lua.eval("migration_origin_110_successor_lifecycle")(
                    "f200", source["name"], wrapper["name"], None, None, False,
                    None, None, False, saved, progress, current_saved))
                self.assertFalse(result["ok"])
                self.assertIn(expected, result["message"])
                if label == "saved":
                    self.assertIn("source{level=1 researched=false enabled=true visible=false maximum=4294967295 saved=0.125}",
                                  result["message"])
                    self.assertIn("actual{level=1 researched=false enabled=true visible=false maximum=4294967295 saved=0.1}",
                                  result["message"])
                self.assertEqual((0, 0), (result["created_labs"], result["player_add_calls"]))
                self.assertFalse(result["saved"])
                self.assertFalse(result["source_state_changed"])
                self.assertFalse(result["active_state_changed"])

    def test_control_retains_the_unearned_foreign_direct_recipe_as_an_exact_zero_key(self):
        self._install_lifecycle_model()
        source = json.loads((SOURCE_FIXTURE / "info.json").read_text(encoding="utf-8"))
        wrapper = json.loads((FIXTURE / "info-f200.json").read_text(encoding="utf-8"))

        accepted = py(self.lua.eval("migration_origin_110_successor_lifecycle")(
            "f200", source["name"], wrapper["name"]))
        self.assertTrue(accepted["ok"], accepted["message"])
        self.assertEqual((0, 0), (accepted["foreign_gear"], accepted["detached_gear"]))
        self.assertEqual((1, 1), (accepted["created_labs"], accepted["player_add_calls"]))

        opponents = (
            ("missing-direct", "foreign saved recipe-bonus count differs"),
            ("extra", "foreign saved recipe-bonus count differs"),
            ("wrong-direct", "foreign saved recipe bonus differs: iron-gear-wheel"),
            ("detached-missing-direct", "detached saved recipe-bonus count differs"),
            ("detached-extra", "detached saved recipe-bonus count differs"),
            ("detached-wrong-direct", "detached saved recipe bonus differs: iron-gear-wheel"),
        )
        for variant, expected in opponents:
            with self.subTest(variant=variant):
                result = py(self.lua.eval("migration_origin_110_successor_lifecycle")(
                    "f200", source["name"], wrapper["name"], None, None, False,
                    None, None, False, None, None, None, None, variant))
                self.assertFalse(result["ok"])
                self.assertIn(expected, result["message"])
                self.assertEqual((0, 0), (result["created_labs"], result["player_add_calls"]))
                self.assertFalse(result["saved"])
                self.assertFalse(result["source_state_changed"])
                self.assertFalse(result["active_state_changed"])

    def test_runtime_row_diagnostic_reads_native_userdata_shape(self):
        self._install_lifecycle_model()
        source = json.loads((SOURCE_FIXTURE / "info.json").read_text(encoding="utf-8"))
        wrapper = json.loads((FIXTURE / "info-f200.json").read_text(encoding="utf-8"))

        class NativePrototype:
            max_level = 4294967295

        class NativeTechnology:
            name = DIRECT
            valid = True
            level = 1
            researched = False
            enabled = True
            visible_when_disabled = False
            saved_progress = .1
            prototype = NativePrototype()

        actual = NativeTechnology()
        self.assertEqual("userdata", self.lua.eval("function(value) return type(value) end")(actual))
        result = py(self.lua.eval("migration_origin_110_successor_lifecycle")(
            "f200", source["name"], wrapper["name"], None, None, False,
            None, None, False, .125, .42, None, actual))
        self.assertFalse(result["ok"])
        self.assertIn("foreign retained source technology differs: recipe-prod-research_gears-1", result["message"])
        self.assertIn("source{level=1 researched=false enabled=true visible=false maximum=4294967295 saved=0.125}",
                      result["message"])
        self.assertIn("actual{level=1 researched=false enabled=true visible=false maximum=4294967295 saved=0.1}",
                      result["message"])
        self.assertNotIn("technology=", result["message"])
        self.assertEqual((0, 0), (result["created_labs"], result["player_add_calls"]))
        self.assertFalse(result["saved"])
        self.assertFalse(result["source_state_changed"])
        self.assertFalse(result["active_state_changed"])

    def test_control_accepts_only_the_exact_native_battery_token_and_current_recipe_float32_token(self):
        self._install_lifecycle_model()
        source = json.loads((SOURCE_FIXTURE / "info.json").read_text(encoding="utf-8"))
        native_recipe_scalar = struct.unpack("<f", struct.pack("<f", .10))[0]
        wrappers = {
            "f200": json.loads((FIXTURE / "info-f200.json").read_text(encoding="utf-8")),
            "f210": json.loads((FIXTURE / "info-f210.json").read_text(encoding="utf-8")),
        }
        for target, wrapper in wrappers.items():
            with self.subTest(target=target):
                result = py(self.lua.eval("migration_origin_110_successor_lifecycle")(
                    target, source["name"], wrapper["name"], None, None, False,
                    None, native_recipe_scalar, False))
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual("worker-robot-battery|0.1", result["source_battery_effect"])
                self.assertEqual((1, 1), (result["created_labs"], result["player_add_calls"]))

    def test_control_refuses_battery_or_recipe_token_drift_before_candidate_writes(self):
        self._install_lifecycle_model()
        source = json.loads((SOURCE_FIXTURE / "info.json").read_text(encoding="utf-8"))
        wrapper = json.loads((FIXTURE / "info-f200.json").read_text(encoding="utf-8"))
        native_recipe_scalar = struct.unpack("<f", struct.pack("<f", .10))[0]
        variants = (
            ("battery", "0.10000000149011612", native_recipe_scalar, False,
             "player saved source effect multiset differs: recipe-prod-research_robot_battery-1"),
            ("scalar", None, native_recipe_scalar + .00000001, False,
             "published source recipe-effect scalar is unsupported"),
            ("multiplicity", None, native_recipe_scalar, True,
             "player current public module effects differ"),
        )
        for label, battery_token, recipe_scalar, duplicate, expected in variants:
            with self.subTest(label=label):
                result = py(self.lua.eval("migration_origin_110_successor_lifecycle")(
                    "f200", source["name"], wrapper["name"], None, None, False,
                    battery_token, recipe_scalar, duplicate))
                self.assertFalse(result["ok"])
                self.assertIn(expected, result["message"])
                self.assertEqual((0, 0), (result["created_labs"], result["player_add_calls"]))
                self.assertFalse(result["saved"])
                self.assertFalse(result["source_state_changed"])
                self.assertFalse(result["active_state_changed"])

    def test_renamed_successor_cannot_consume_the_protected_source_storage(self):
        self._install_lifecycle_model()
        source = json.loads((SOURCE_FIXTURE / "info.json").read_text(encoding="utf-8"))
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                result = py(self.lua.eval("migration_origin_110_successor_lifecycle")(
                    target, source["name"], RETIRED_SUCCESSOR_NAME, RETIRED_SUCCESSOR_NAME))
                self.assertFalse(result["ok"])
                self.assertIn("protected MIR 1.1 source state is absent", result["message"])
                self.assertNotIn("successor runtime target closure differs", result["message"])
                self.assertEqual(0, result["created_labs"])
                self.assertEqual(0, result["player_add_calls"])
                self.assertFalse(result["source_state_changed"])
                self.assertFalse(result["active_state_changed"])

    def test_legacy_tier_one_module_ten_percent_is_refused_before_candidate_lab_or_successor_write(self):
        self._install_lifecycle_model()
        source = json.loads((SOURCE_FIXTURE / "info.json").read_text(encoding="utf-8"))
        wrappers = {
            "f200": json.loads((FIXTURE / "info-f200.json").read_text(encoding="utf-8")),
            "f210": json.loads((FIXTURE / "info-f210.json").read_text(encoding="utf-8")),
        }
        for target, wrapper in wrappers.items():
            with self.subTest(target=target):
                result = py(self.lua.eval("migration_origin_110_successor_lifecycle")(
                    target, source["name"], wrapper["name"], None, .10))
                self.assertFalse(result["ok"])
                self.assertRegex(result["message"],
                                 r"player retained source recipe contribution differs: (speed|productivity|efficiency)-module")
                self.assertEqual((0, 0), (result["created_labs"], result["player_add_calls"]))
                self.assertFalse(result["saved"])
                self.assertEqual(0, result["player_reset_calls"])
                observations = [json.loads(value.split(" OBSERVED ", 1)[1]) for value in result["logs"]
                                if value.startswith("[MIR5_NATIVE_FIXTURE] OBSERVED ")]
                self.assertTrue(any((.11, .11, .11, .1, .1, .1) ==
                                    (value["original_source_speed_module_bonus"],
                                     value["original_source_productivity_module_bonus"],
                                     value["original_source_efficiency_module_bonus"],
                                     value["current_candidate_speed_module_bonus"],
                                     value["current_candidate_productivity_module_bonus"],
                                     value["current_candidate_efficiency_module_bonus"])
                                    for value in observations))
                self.assertFalse(result["source_state_changed"])
                self.assertFalse(result["active_state_changed"])

    def test_candidate_effect_reset_refuses_to_save_when_it_loses_the_saved_module_one_percent(self):
        self._install_lifecycle_model()
        source = json.loads((SOURCE_FIXTURE / "info.json").read_text(encoding="utf-8"))
        wrappers = {
            "f200": json.loads((FIXTURE / "info-f200.json").read_text(encoding="utf-8")),
            "f210": json.loads((FIXTURE / "info-f210.json").read_text(encoding="utf-8")),
        }
        for target, wrapper in wrappers.items():
            with self.subTest(target=target):
                result = py(self.lua.eval("migration_origin_110_successor_lifecycle")(
                    target, source["name"], wrapper["name"], None, None, True))
                self.assertFalse(result["ok"])
                self.assertRegex(result["message"],
                                 r"player retained source recipe contribution differs: (speed|productivity|efficiency)-module")
                self.assertEqual((1, 1), (result["created_labs"], result["player_add_calls"]))
                self.assertEqual((1, 0, 0), (result["player_reset_calls"], result["foreign_reset_calls"], result["detached_reset_calls"]))
                self.assertEqual(["reset:player"], result["order"])
                self.assertFalse(result["saved"])
                self.assertEqual("await-observation", result["state"]["successors"][target]["phase"])
                self.assertFalse(any(value.startswith("[MIR5_NATIVE_FIXTURE] RESULT ") for value in result["logs"]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    MigrationOriginF200110SuccessorControls.lua = LuaRuntime(unpack_returned_tuples=True)
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(MigrationOriginF200110SuccessorControls))
    sys.exit(0 if result.wasSuccessful() else 1)

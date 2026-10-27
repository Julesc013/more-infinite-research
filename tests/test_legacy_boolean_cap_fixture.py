"""Independent controls for the published F200 policy-v1 boolean-cap fixture.

These controls prepare native inputs only.  They do not model Factorio's old
controller, a save migration, or a laboratory result.
"""
import argparse
import copy
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/legacy-boolean-cap"
SOURCE = FIXTURE / "published"
F200 = FIXTURE / "f200/successor"
F210 = FIXTURE / "f210/successor"
SOURCE_PROFILE = ROOT / "tests/profiles/legacy-boolean-cap-published-400-f200-2077.json"
F200_PROFILE = ROOT / "tests/profiles/legacy-boolean-cap-current-f200-2077.json"
F210_PROFILE = ROOT / "tests/profiles/legacy-boolean-cap-current-f210-2123.json"
ARCHIVE_SHA256 = "5C0E299D78C4EE545958448DAE48D87BE5FE1B959875D4CB93A264D95D3DB0AE"
POLICY_SHA256 = "687E2EB214C7097C1691562ECE206AA69FDE24194164A8EF33F48AF14405C0EA"
GEAR = "recipe-prod-research_gears-1"
SCIENCE = [
    ["automation-science-pack", 1], ["logistic-science-pack", 1],
    ["chemical-science-pack", 1], ["production-science-pack", 1],
]


def py(value):
    if hasattr(value, "items"):
        keys = list(value.keys())
        if keys and all(isinstance(key, int) and key > 0 for key in keys) and set(keys) == set(range(1, len(keys) + 1)):
            return [py(value[index]) for index in range(1, len(keys) + 1)]
        return {key: py(item) for key, item in value.items()}
    return value


def lua(runtime, value):
    if isinstance(value, dict):
        return runtime.table_from({key: lua(runtime, item) for key, item in value.items()})
    if isinstance(value, list):
        return runtime.table_from([lua(runtime, item) for item in value])
    return value


class LegacyBooleanCapFixtureTests(unittest.TestCase):
    def row(self):
        return {
            "type": "technology", "name": GEAR, "upgrade": True, "max_level": "infinite",
            "enabled": True,
            "unit": {"count_formula": "8000*2^(L-1)", "time": 60,
                     "ingredients": copy.deepcopy(SCIENCE)},
            "effects": [{"type": "change-recipe-productivity", "recipe": "iron-gear-wheel", "change": .10}],
        }

    def run_data(self, path, raw, mods):
        self.lua.globals().fixture_data_path = path.as_posix()
        self.lua.execute(r'''
          function legacy_boolean_cap_data(raw, mods)
            local env={data={raw=raw},mods=mods}
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(fixture_data_path,"t",env))() end)
            return {ok=ok,message=tostring(message),raw=raw}
          end
        ''')
        return py(self.lua.eval("legacy_boolean_cap_data")(lua(self.lua, copy.deepcopy(raw)), lua(self.lua, mods)))

    def run_settings(self, path, mods):
        self.lua.globals().fixture_settings_path = path.as_posix()
        self.lua.execute(r'''
          function legacy_boolean_cap_settings(mods)
            local cap={default_value=0,minimum_value=0,maximum_value=2147483647}
            local effect={default_value=10}
            local env={mods=mods,data={raw={ ["int-setting"]={ ["ips-max-level-research_gears"]=cap },
              ["double-setting"]={ ["ips-effect-per-level-research_gears"]=effect }}}}
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(fixture_settings_path,"t",env))() end)
            return {ok=ok,message=tostring(message),cap=cap,effect=effect}
          end
        ''')
        return py(self.lua.eval("legacy_boolean_cap_settings")(lua(self.lua, mods)))

    def parse_control(self, path, mods):
        self.lua.globals().fixture_control_path = path.as_posix()
        self.lua.execute(r'''
          function legacy_boolean_cap_parse(mods)
            local callbacks,forbidden={events={}},{}
            local env={script={active_mods=mods,on_init=function(fn) callbacks.init=fn end,
              on_load=function(fn) callbacks.load=fn end,on_configuration_changed=function(fn) callbacks.configuration=fn end,
              on_event=function(event,fn) callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}}
            env._G=env;setmetatable(env,{__index=function(_,key)
              if key=="game" or key=="storage" or key=="settings" then forbidden[key]=true;return nil end
              return _G[key]
            end})
            local ok,message=pcall(function() assert(loadfile(fixture_control_path,"t",env))() end)
            return {ok=ok,message=tostring(message),callbacks=callbacks,forbidden=forbidden}
          end
        ''')
        return py(self.lua.eval("legacy_boolean_cap_parse")(lua(self.lua, mods)))

    def source_flow(self, keep_enabled=False):
        self.lua.globals().fixture_source_control_path = (SOURCE / "control.lua").as_posix()
        self.lua.execute(r'''
          function legacy_boolean_cap_source_flow(keep_enabled)
            local callbacks,markers,saves={events={}},{},0
            local science={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}
            local function inventory()
              local value={counts={}}
              function value.insert(request) value.counts[request.name]=(value.counts[request.name] or 0)+request.count;return request.count end
              function value.get_item_count(name) return value.counts[name] or 0 end
              return value
            end
            local function technology(name,force)
              return {name=name,force=force,valid=true,level=1,researched=false,enabled=true,visible_when_disabled=true,
                saved_progress=0,prerequisites={},prototype={max_level=4294967295},research_unit_count=1,research_unit_energy=60,
                research_unit_ingredients={{name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1},
                  {name="chemical-science-pack",amount=1},{name="production-science-pack",amount=1}}}
            end
            local function force(name,index)
              local value={name=name,index=index,valid=true,technologies={},recipes={["iron-gear-wheel"]={productivity_bonus=0}},
                research_queue={},research_progress=0}
              local gear=technology("recipe-prod-research_gears-1",value)
              value.technologies[gear.name]=gear
              value.technologies["braking-force-1"]=technology("braking-force-1",value)
              function value.enable_all_prototypes() end
              function value.reset_technology_effects() end
              function value.add_research(research)
                if research==nil or value.current_research~=nil then return false end
                value.current_research=research;value.research_queue={research};value.research_progress=research.saved_progress or 0;return true
              end
              return value
            end
            local player=force("player",1)
            local game={tick=0,forces={player=player,[1]=player},surfaces={[1]={}}}
            game.surfaces[1].create_entity=function(request)
              local result={valid=true,energy=0,force=request.force,contents=inventory()}
              function result.get_inventory(kind) return result.contents end
              return result
            end
            function game.create_force(name)
              local result=force(name,2);game.forces[name]=result;game.forces[2]=result;return result
            end
            function game.server_save(name) assert(name=="mir5-native-complete");saves=saves+1 end
            local storage={}
            local env={game=game,storage=storage,settings={startup={
              ["ips-max-level-research_gears"]={value=2},["ips-effect-per-level-research_gears"]={value=10}}},
              helpers={table_to_json=function(row)markers[#markers+1]=row;return "{}" end},
              log=function(value)assert(value:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "))end,
              script={active_mods={base="2.0.77",["more-infinite-research"]="4.0.20000",
                  ["mir-fixture-mir5-legacy-boolean-cap"]="0.1.0"},
                on_init=function(fn)callbacks.init=fn end,on_load=function(fn)callbacks.load=fn end,
                on_event=function(event,fn)callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}}
            env._G=env;setmetatable(env,{__index=_G})
            local chunk,message=loadfile(fixture_source_control_path,"t",env);assert(chunk,message);chunk()
            local function invoke(callback,argument) local ok,message=pcall(callback,argument);return ok,tostring(message) end
            local function tick() game.tick=game.tick+1;return invoke(callbacks.events[2]) end
            local ok,message=invoke(callbacks.init);if not ok then return {ok=false,message=message} end
            local state=storage.mir5_legacy_boolean_cap;local gear=player.technologies["recipe-prod-research_gears-1"]
            -- These two assignments and inventory decrements model exactly the native
            -- laboratory completions asserted by the fixture; the fixture remains the
            -- only code that observes and records the capped state.
            player.current_research=nil;player.research_queue={};gear.level=2;player.recipes["iron-gear-wheel"].productivity_bonus=.10
            for _,name in ipairs(science) do state.lab.contents.counts[name]=state.lab.contents.counts[name]-1 end
            ok,message=invoke(callbacks.events[1],{research=gear});if not ok then return {ok=false,message=message} end
            ok,message=tick();if not ok then return {ok=false,message=message} end
            player.current_research=nil;player.research_queue={};gear.level=3;player.recipes["iron-gear-wheel"].productivity_bonus=.20
            if not keep_enabled then gear.enabled=false end
            for _,name in ipairs(science) do state.lab.contents.counts[name]=state.lab.contents.counts[name]-1 end
            ok,message=invoke(callbacks.events[1],{research=gear});if not ok then return {ok=false,message=message} end
            if keep_enabled then game.tick=state.deadline_tick+1 else game.tick=game.tick+1 end
            ok,message=invoke(callbacks.events[2]);if not ok then return {ok=false,message=message} end
            for _=1,2 do
              ok,message=invoke(callbacks.load);if not ok then return {ok=false,message=message} end
              ok,message=tick();if not ok then return {ok=false,message=message} end
            end
            return {ok=true,saves=saves,markers=markers,state={actual_lab_completions=storage.mir5_legacy_boolean_cap.actual_lab_completions,
                milestone=storage.mir5_legacy_boolean_cap.milestone,player_cap=storage.mir5_legacy_boolean_cap.player_cap},
              player={level=gear.level,enabled=gear.enabled,visible=gear.visible_when_disabled,
                progress=gear.saved_progress,bonus=player.recipes["iron-gear-wheel"].productivity_bonus},
              foreign={level=game.forces[2].technologies["recipe-prod-research_gears-1"].level,
                enabled=game.forces[2].technologies["recipe-prod-research_gears-1"].enabled,
                visible_when_disabled=game.forces[2].technologies["recipe-prod-research_gears-1"].visible_when_disabled}}
          end
        ''')
        return py(self.lua.eval("legacy_boolean_cap_source_flow")(keep_enabled))

    def test_data_preflights_pin_the_independent_published_and_successor_row_before_acceleration(self):
        stages = (
            (SOURCE / "data-final-fixes.lua", {"base": "2.0.77", "more-infinite-research": "4.0.20000",
                                                 "mir-fixture-mir5-legacy-boolean-cap": "0.1.0"}),
            (F200 / "data-final-fixes.lua", {"base": "2.0.77", "more-infinite-research": "5.0.20000",
                                               "mir-fixture-mir5-legacy-boolean-cap": "0.2.0"}),
            (F210 / "data-final-fixes.lua", {"base": "2.1.23", "more-infinite-research": "5.0.21000",
                                               "mir-fixture-mir5-legacy-boolean-cap": "0.3.0"}),
        )
        for path, mods in stages:
            with self.subTest(path=path):
                raw = {"technology": {GEAR: self.row()}, "sentinel": {"unchanged": 17}}
                accepted = self.run_data(path, raw, mods)
                self.assertTrue(accepted["ok"], accepted["message"])
                unit = accepted["raw"]["technology"][GEAR]["unit"]
                self.assertEqual((1, None, 1), (unit["count"], unit.get("count_formula"), unit["time"]))
                self.assertEqual(SCIENCE, unit["ingredients"])
                self.assertEqual(17, accepted["raw"]["sentinel"]["unchanged"])

                for label, mutate in (
                    ("formula", lambda row: row["unit"].update({"count_formula": "8001*2^(L-1)"})),
                    ("science", lambda row: row["unit"]["ingredients"].__setitem__(0, ["foreign-science-pack", 1])),
                    ("effect", lambda row: row["effects"][0].update({"change": .01})),
                ):
                    candidate = {"technology": {GEAR: self.row()}, "sentinel": {"unchanged": 17}}
                    mutate(candidate["technology"][GEAR])
                    before = copy.deepcopy(candidate)
                    rejected = self.run_data(path, candidate, mods)
                    self.assertFalse(rejected["ok"], (label, rejected["message"]))
                    self.assertEqual(before, rejected["raw"])

    def test_settings_stages_select_only_the_historical_source_cap(self):
        source_mods = {"base": "2.0.77", "more-infinite-research": "4.0.20000",
                       "mir-fixture-mir5-legacy-boolean-cap": "0.1.0"}
        source = self.run_settings(SOURCE / "settings-updates.lua", source_mods)
        self.assertTrue(source["ok"], source["message"])
        self.assertEqual((2, 10), (source["cap"]["default_value"], source["effect"]["default_value"]))
        for path, mods in (
            (F200 / "settings-updates.lua", {"base": "2.0.77", "more-infinite-research": "5.0.20000",
                                               "mir-fixture-mir5-legacy-boolean-cap": "0.2.0"}),
            (F210 / "settings-updates.lua", {"base": "2.1.23", "more-infinite-research": "5.0.21000",
                                               "mir-fixture-mir5-legacy-boolean-cap": "0.3.0"}),
        ):
            with self.subTest(path=path):
                result = self.run_settings(path, mods)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual((0, 10), (result["cap"]["default_value"], result["effect"]["default_value"]))

    def test_controls_register_only_the_required_source_or_successor_callbacks(self):
        source = self.parse_control(SOURCE / "control.lua", {"base": "2.0.77", "more-infinite-research": "4.0.20000",
                                                                "mir-fixture-mir5-legacy-boolean-cap": "0.1.0"})
        self.assertTrue(source["ok"], source["message"])
        self.assertIsNotNone(source["callbacks"]["init"])
        self.assertIsNotNone(source["callbacks"]["load"])
        self.assertIsNone(source["callbacks"].get("configuration"))
        self.assertEqual({}, source["forbidden"])
        for path, mods in (
            (F200 / "control.lua", {"base": "2.0.77", "more-infinite-research": "5.0.20000",
                                      "mir-fixture-mir5-legacy-boolean-cap": "0.2.0"}),
            (F210 / "control.lua", {"base": "2.1.23", "more-infinite-research": "5.0.21000",
                                      "mir-fixture-mir5-legacy-boolean-cap": "0.3.0"}),
        ):
            with self.subTest(path=path):
                result = self.parse_control(path, mods)
                self.assertTrue(result["ok"], result["message"])
                self.assertIsNotNone(result["callbacks"]["configuration"])
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertEqual({}, result["forbidden"])

    def test_published_archive_provenance_and_prepared_profiles_bind_the_reviewed_candidate_packages(self):
        metadata = json.loads((ROOT / "spec/evidence/historical-boolean-cap-archive-metadata.json").read_text(encoding="utf-8"))
        observed = next(row for row in metadata["observations"] if row["info_json"]["version"] == "4.0.20000")
        self.assertEqual((1067014, ARCHIVE_SHA256, POLICY_SHA256,
                          "09eb",
                          "67c3f06c0af3de8193548e1716e7aba8d5380135"),
                         (observed["archive"]["observed_bytes"], observed["archive"]["observed_sha256"],
                          observed["maximum_level_control"]["raw_sha256"],
                          observed["maximum_level_control"]["matched_git_body"],
                          observed["maximum_level_control"]["tag_source_git_blob"]))
        source = json.loads(SOURCE_PROFILE.read_text(encoding="utf-8"))
        self.assertEqual(ARCHIVE_SHA256, source["archive_sha256"]["more-infinite-research_4.0.20000.zip"])
        self.assertEqual(("4.0.0", "09eb6ece484c8e3c1bcdafaea31451ce84a27108"),
                         (source["origin_tag"], source["origin_archive_body"]))
        for profile_path, target, mir, fixture, archive, digest, size in (
            (F200_PROFILE, "f200", "5.0.20000", "0.2.0", "more-infinite-research_5.0.20000.zip",
             "7450900FB863D86A9A798E130965959FE9731FAD1DFAE592B69707358343604C", 680580),
            (F210_PROFILE, "f210", "5.0.21000", "0.3.0", "more-infinite-research_5.0.21000.zip",
             "F2D19181643C757649DC28A317917CC0806D651D0A7EFA8BDAB4C69DFF6EAFF5", 680964),
        ):
            profile = json.loads(profile_path.read_text(encoding="utf-8"))
            with self.subTest(profile=profile_path.name):
                self.assertEqual({archive: digest}, profile["archive_sha256"])
                self.assertEqual(("8465e2a2c0dbab16a3260e6bab86bcadddb4f997",
                                  "2c4d9253ff2f427d528726a402cc7f8547130d0d", size),
                                 (profile["candidate_binding"]["source_commit"],
                                  profile["candidate_binding"]["player_tree"],
                                  profile["candidate_binding"]["bytes"]))
                self.assertEqual((target, mir, fixture),
                                 (profile["target"], next(row["version"] for row in profile["mods"]
                                                           if row["name"] == "more-infinite-research"),
                                  next(row["version"] for row in profile["mods"]
                                       if row["name"] == "mir-fixture-mir5-legacy-boolean-cap")))

    def test_source_proves_native_transition_without_cross_mod_storage_access_and_successors_remain_distinct(self):
        source = (SOURCE / "control.lua").read_text(encoding="utf-8")
        self.assertNotIn("storage.mir", source)
        self.assertNotIn("maximum_level_control", source)
        self.assertIn("player.enabled == false and player.visible == true", source)
        self.assertIn("foreign_gear.enabled = false", source)
        self.assertIn("foreign_gear.visible_when_disabled = false", source)
        self.assertIn("actual_lab_completions ~= 2", source)
        self.assertIn("game.server_save(SAVE)", source)
        self.assertIn('marker("reload", state)', source)
        f200 = (F200 / "control.lua").read_text(encoding="utf-8")
        f210 = (F210 / "control.lua").read_text(encoding="utf-8")
        self.assertIn("F200 restored player", f200)
        self.assertIn("F210 direct restored player", f210)
        self.assertIn("script.active_mods.base ~= \"2.1.23\"", f210)
        self.assertIn("direct successor carries Space Age companions", f210)
        for control in (f200, f210):
            self.assertIn("foreign gear", control)
            self.assertIn("destination_lab_completions ~= 1", control)
            self.assertIn("game.server_save(SAVE)", control)
            self.assertIn('marker("reload", state)', control)

    def test_native_shaped_source_model_requires_the_observed_cap_disablement_before_the_protected_save(self):
        passed = self.source_flow()
        self.assertTrue(passed["ok"], passed.get("message"))
        self.assertEqual(1, passed["saves"])
        self.assertEqual(["initial", "reload", "reload"], [row["stage"] for row in passed["markers"]])
        self.assertEqual((3, False, True, .27, .20),
                         (passed["player"]["level"], passed["player"]["enabled"], passed["player"]["visible"],
                          passed["player"]["progress"], passed["player"]["bonus"]))
        self.assertEqual((1, False, False),
                         (passed["foreign"]["level"], passed["foreign"]["enabled"],
                          passed["foreign"]["visible_when_disabled"]))
        self.assertEqual((2, "actual2labs", .27),
                         (passed["state"]["actual_lab_completions"], passed["state"]["milestone"],
                          passed["state"]["player_cap"]["saved_progress"]))

        refused = self.source_flow(keep_enabled=True)
        self.assertFalse(refused["ok"])
        self.assertIn("source labs did not complete", refused["message"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    LegacyBooleanCapFixtureTests.lua = LuaRuntime(unpack_returned_tuples=True)
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LegacyBooleanCapFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

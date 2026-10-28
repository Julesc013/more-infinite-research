"""Host controls for the bounded K2SE hidden Imersite carrier save fixture.

These controls exercise the fixture callbacks with native-shaped force and
technology doubles.  They are not Factorio execution or a K2SO handoff claim.
"""
import argparse
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/k2se-imersite-carrier-retention"
SUCCESSOR_ROLE = "successor"
BASE_PROFILE = ROOT / "tests/profiles/k2se-base-f210-2123.json"
PUBLISHED_PROFILE = ROOT / "tests/profiles/k2se-imersite-carriers-published-4.7-f210-2123.json"
SUCCESSOR_PROFILE = ROOT / "tests/profiles/k2se-imersite-carriers-mir5-f210-2123.json"
FREEZE = ROOT / "spec/evidence/current-assets-b251ae7a-aero-readback.json"
ENGINE_SHA = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"
PUBLISHED_SHA = "B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852"
SUCCESSOR_SHA = "E3A65C08AC7798A66FB1BE30D24307B17C8B366DD901953BDE2A09BD6939C8CE"
SUCCESSOR_BYTES = 679250
SUCCESSOR_SOURCE = "b251ae7a54104ace87cb0da4cf531cf53f03c93d"
SUCCESSOR_SOURCE_TREE = "79b73a6a8e68987737e69bf2d95ec6555b49f901"
EARLY = "mir-k2-imersite-staged-state-1"
TAIL = "mir-k2-imersite-continuation-state-4"


def fixture_role(stage):
    return SUCCESSOR_ROLE if stage == "mir5" else stage
OBSERVER = "mir-fixture-mir5-active-mods-observer_0.1.0.zip"


def as_plain(value):
    if not hasattr(value, "items"):
        return value
    keys = list(value.keys())
    if keys and all(isinstance(key, int) for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [as_plain(value[index]) for index in range(1, len(keys) + 1)]
    return {key: as_plain(item) for key, item in value.items()}


class K2SEImersiteCarrierFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
          function carrier_data(path, stage, opponent)
            local function row(name, first, formula)
              return {type="technology",name=name,level=first,hidden=true,upgrade=false,enabled=true,
                max_level="infinite",prerequisites={},effects={{type="change-recipe-productivity",
                recipe="kr-imersite-powder",change=.02}},unit={count_formula=formula,time=30,
                ingredients={{"automation-science-pack",1}}}}
            end
            local early=row("mir-k2-imersite-staged-state-1",1,"200*2^(L-1)")
            local tail=row("mir-k2-imersite-continuation-state-4",4,"1600+200*(L-4)")
            if opponent=="missing-tail" then rawset(tail,"name",nil) end
            if opponent=="wrong-effect" then tail.effects[1].change=.03 end
            if opponent=="missing-science" then tail.unit.ingredients={} end
            local raw={technology={ ["mir-k2-imersite-staged-state-1"]=early,
              ["mir-k2-imersite-continuation-state-4"]=tail }}
            if opponent=="missing-tail" then raw.technology["mir-k2-imersite-continuation-state-4"]=nil end
            local mods={base="2.1.23",Krastorio2="2.1.4",["space-exploration"]="0.7.63",
              ["more-infinite-research"]=stage=="published" and "4.7.21003" or "5.0.21000",
              ["mir-fixture-mir5-k2se-imersite-carrier-retention"]=stage=="published" and "0.1.0" or "0.2.0"}
            local env={mods=mods,data={raw=raw}};env._G=env
            setmetatable(env,{__index=function(_,key)return _G[key]end})
            local chunk,message=loadfile(path,"t",env);assert(chunk,message)
            local ok,result=pcall(chunk)
            return {ok=ok,message=tostring(result),early=early,tail=tail}
          end

          function carrier_parse(path, stage)
            local callbacks,reads={events={}},{game=0,storage=0}
            local env={script={active_mods={base="2.1.23",Krastorio2="2.1.4",["space-exploration"]="0.7.63",
              ["more-infinite-research"]=stage=="published" and "4.7.21003" or "5.0.21000",
              ["mir-fixture-mir5-k2se-imersite-carrier-retention"]=stage=="published" and "0.1.0" or "0.2.0"},
              on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.changed=f end,
              on_load=function(f)callbacks.load=f end,on_event=function(e,f)callbacks.events[e]=f end},
              defines={events={on_tick=1}}}
            env._G=env;setmetatable(env,{__index=function(_,key)
              if key=="game" or key=="storage" then reads[key]=reads[key]+1 end
              return _G[key]
            end})
            local chunk,message=loadfile(path,"t",env);assert(chunk,message)
            local ok,result=pcall(chunk)
            return {ok=ok,message=tostring(result),callbacks=callbacks,reads=reads}
          end

          function carrier_flow(source_path, successor_path, opponent)
            local markers,saves,callbacks={},0,nil
            local function tech(name, first)
              return {name=name,valid=true,level=first,researched=false,enabled=true,
                visible_when_disabled=false,saved_progress=0,
                prototype={hidden=true,max_level=4294967295,level=first,upgrade=false,
                  effects={{type="change-recipe-productivity",recipe="kr-imersite-powder",change=.02}}}}
            end
            local function make_force(name)
              local value={name=name,valid=true,technologies={
                ["mir-k2-imersite-staged-state-1"]=tech("mir-k2-imersite-staged-state-1",1),
                ["mir-k2-imersite-continuation-state-4"]=tech("mir-k2-imersite-continuation-state-4",4)},
                recipes={['kr-imersite-powder']={productivity_bonus=0}},research_queue={},research_progress=0}
              function value.enable_all_prototypes() end
              function value.reset_technology_effects()
                local early,tail=value.technologies["mir-k2-imersite-staged-state-1"],value.technologies["mir-k2-imersite-continuation-state-4"]
                value.recipes['kr-imersite-powder'].productivity_bonus=((early.level-1)+(tail.level-4))*.02
                if opponent=="setup-resets-progress" then value.research_progress=0 end
              end
              function value.add_research(research)
                if research==nil or research.enabled~=true then return false end
                if value.current_research==nil then
                  value.current_research=research;value.research_progress=research.saved_progress;research.saved_progress=0
                end
                value.research_queue[#value.research_queue+1]=research
                return true
              end
              return value
            end
            local player=make_force("player")
            local game={forces={player=player},tick=0}
            function game.create_force(name)
              local value=make_force(name);game.forces[name]=value
              if opponent=="force-created-clears-player-investment" then
                player.current_research=nil;player.research_queue={};player.research_progress=0
              end
              return value
            end
            function game.server_save(name) assert(name=="mir5-native-complete");saves=saves+1 end
            local storage={}
            local settings={startup={
              ["ips-enable-research_material_imersite"]={value=true},
              ["ips-cost-base-research_material_imersite"]={value=200},
              ["ips-cost-linear-increment-research_material_imersite"]={value=0},
              ["ips-cost-growth-research_material_imersite"]={value=2},
              ["ips-max-level-research_material_imersite"]={value=3},
              ["ips-research-time-research_material_imersite"]={value=30},
              ["ips-effect-per-level-research_material_imersite"]={value=2}}}
            local function load_control(path, stage)
              local result={events={}}
              local env={game=game,storage=storage,settings=settings,defines={events={on_tick=1}},
                helpers={table_to_json=function(row) markers[#markers+1]=row;return "{}" end},log=function(value)
                  assert(value:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "))end,
                script={active_mods={base="2.1.23",Krastorio2="2.1.4",["space-exploration"]="0.7.63",
                  ["more-infinite-research"]=stage=="published" and "4.7.21003" or "5.0.21000",
                  ["mir-fixture-mir5-k2se-imersite-carrier-retention"]=stage=="published" and "0.1.0" or "0.2.0"},
                  on_init=function(f)result.init=f end,on_configuration_changed=function(f)result.changed=f end,
                  on_load=function(f)result.load=f end,on_event=function(e,f)result.events[e]=f end}}
              env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
              local chunk,message=loadfile(path,"t",env);assert(chunk,message);chunk()
              return result
            end
            local source=load_control(source_path,"published")
            local ok,message=pcall(source.init);if not ok then return {ok=false,message=tostring(message),markers=markers,saves=saves,storage=storage} end
            game.tick=game.tick+1;ok,message=pcall(source.events[1]);if not ok then return {ok=false,message=tostring(message),markers=markers,saves=saves,storage=storage} end
            ok,message=pcall(source.load);if not ok then return {ok=false,message=tostring(message),markers=markers,saves=saves,storage=storage} end
            game.tick=game.tick+1;ok,message=pcall(source.events[1]);if not ok then return {ok=false,message=tostring(message),markers=markers,saves=saves,storage=storage} end
            if opponent=="foreign-enabled" then game.forces["mir5-k2se-imersite-carrier-foreign"].technologies["mir-k2-imersite-continuation-state-4"].enabled=true end
            if opponent=="lost-successor-progress" then player.research_progress=0 end
            local successor=load_control(successor_path,"successor")
            ok,message=pcall(successor.changed)
            if not ok then return {ok=false,message=tostring(message),markers=markers,saves=saves,storage=storage} end
            game.tick=game.tick+1;ok,message=pcall(successor.events[1]);if not ok then return {ok=false,message=tostring(message),markers=markers,saves=saves,storage=storage} end
            ok,message=pcall(successor.load);if not ok then return {ok=false,message=tostring(message),markers=markers,saves=saves,storage=storage} end
            game.tick=game.tick+1;ok,message=pcall(successor.events[1])
            return {ok=ok,message=tostring(message),markers=markers,saves=saves,storage=storage,
              player=player,foreign=game.forces["mir5-k2se-imersite-carrier-foreign"]}
          end
        ''')

    def _data(self, stage, opponent=""):
        return self.lua.eval("carrier_data")(
            str(FIXTURE / fixture_role(stage) / "data-final-fixes.lua"), "published" if stage == "published-4.7" else "mir5", opponent)

    def test_profiles_preserve_exact_q013_closure_and_select_only_two_mir_fixture_arms(self):
        base = json.loads(BASE_PROFILE.read_text(encoding="utf-8"))
        expected = {
            "published-4.7": (PUBLISHED_PROFILE, "4.7.21003", "0.1.0", PUBLISHED_SHA),
            "mir5": (SUCCESSOR_PROFILE, "5.0.21000", "0.2.0", SUCCESSOR_SHA),
        }
        for stage, (path, mir, fixture, digest) in expected.items():
            with self.subTest(stage=stage):
                profile = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual((1, "mir5-k2se-imersite-carriers-f210-native-selection", "f210", "2.1", "Defaults"),
                                 (profile["schema"], profile["kind"], profile["target"], profile["factorio_line"], profile["settings_mode"]))
                self.assertEqual(("2.1.23", ENGINE_SHA), (profile["engine"]["version"], profile["engine"]["sha256"]))
                rows = {row["name"]: row["version"] for row in profile["mods"]}
                self.assertEqual(mir, rows.pop("more-infinite-research"))
                self.assertEqual(fixture, rows.pop("mir-fixture-mir5-k2se-imersite-carrier-retention"))
                self.assertEqual({row["name"]: row["version"] for row in base["mods"]}, rows)
                self.assertNotIn("Krastorio2-spaced-out", rows)
                archives = dict(profile["archive_sha256"])
                self.assertEqual(digest, archives.pop(f"more-infinite-research_{mir}.zip"))
                self.assertEqual(base["archive_sha256"], archives)
                self.assertEqual("A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0", archives[OBSERVER])
        freeze = json.loads(FREEZE.read_text(encoding="utf-8"))
        self.assertEqual((SUCCESSOR_SOURCE, SUCCESSOR_SOURCE_TREE),
                         (freeze["source"]["commit"], freeze["source"]["source_tree"]))
        asset = next(row for row in freeze["files"] if row["name"] == "more-infinite-research_5.0.21000.zip")
        self.assertEqual((SUCCESSOR_BYTES, SUCCESSOR_SHA), (asset["bytes"], asset["sha256"]))
        scope = json.loads(SUCCESSOR_PROFILE.read_text(encoding="utf-8"))["scope"]
        for expected in (SUCCESSOR_SOURCE, SUCCESSOR_SOURCE_TREE, SUCCESSOR_SHA, f"{SUCCESSOR_BYTES} bytes"):
            self.assertIn(expected, scope)
        self.assertNotIn("C563CB5B96C9E64CB3373BDB60CF5C8B7D3C97E93EADB8F924443C703CDC024D", scope)

    def test_data_preflight_checks_both_hidden_rows_without_fixture_mutation(self):
        for stage in ("published-4.7", "mir5"):
            with self.subTest(stage=stage):
                result = self._data(stage)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual((1, 4), (result["early"]["level"], result["tail"]["level"]))
                self.assertEqual(.02, result["tail"]["effects"][1]["change"])
        for opponent, phrase in (("missing-tail", "carrier is absent"), ("wrong-effect", "carrier effect changed"),
                                  ("missing-science", "carrier science is absent")):
            with self.subTest(opponent=opponent):
                result = self._data("mir5", opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
                self.assertEqual(.03 if opponent == "wrong-effect" else .02, result["tail"]["effects"][1]["change"])

    def test_controls_register_without_game_or_storage_reads_and_on_load_is_read_only(self):
        for stage in ("published-4.7", "mir5"):
            with self.subTest(stage=stage):
                parsed = self.lua.eval("carrier_parse")(str(FIXTURE / fixture_role(stage) / "control.lua"), "published" if stage == "published-4.7" else "successor")
                self.assertTrue(parsed["ok"], parsed["message"])
                self.assertEqual((0, 0), (parsed["reads"]["game"], parsed["reads"]["storage"]))
                self.assertIsNotNone(parsed["callbacks"]["load"])
                self.assertIsNotNone(parsed["callbacks"]["events"][1])
                source = (FIXTURE / fixture_role(stage) / "control.lua").read_text(encoding="utf-8")
                on_load = source.split("script.on_load", 1)[1].split("script.on_event", 1)[0]
                self.assertNotIn("game.", on_load)
                self.assertNotIn("storage", on_load)

    def test_source_then_successor_retains_native_seeded_carriers_through_two_reload_callbacks(self):
        result = self.lua.eval("carrier_flow")(str(FIXTURE / "published-4.7/control.lua"), str(FIXTURE / "successor/control.lua"), "")
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual(2, result["saves"])
        markers = [as_plain(result["markers"][index]) for index in range(1, 5)]
        self.assertEqual(["initial", "reload", "initial", "reload"], [marker["stage"] for marker in markers])
        self.assertEqual(("k2se-imersite-carrier-retention-source", "k2se-imersite-carrier-retention-successor"),
                         (markers[0]["case"], markers[2]["case"]))
        for marker in markers:
            witness = marker["witnesses"]
            self.assertTrue(witness["native_saved_state_seeds"])
            self.assertFalse(witness["k2so_runtime_bridge_exercised"])
            self.assertEqual(0, witness.get("source_actual_lab_completions"))
        self.assertEqual((TAIL, 2, .42, .10),
                         (markers[2]["witnesses"]["player_current"], markers[2]["witnesses"]["player_queue_count"],
                          markers[2]["witnesses"]["player_research_progress"], markers[2]["witnesses"]["player_powder_productivity"]))
        self.assertEqual((.27, True, .10),
                         (markers[3]["witnesses"]["foreign_tail_saved_progress"], markers[3]["witnesses"]["foreign_disabled"],
                          markers[3]["witnesses"]["foreign_powder_productivity"]))
        self.assertEqual("successor-complete", result["storage"]["mir5_k2se_imersite_carrier_retention"]["phase"])

    def test_source_establishes_its_seed_after_force_and_effect_setup(self):
        for opponent in ("force-created-clears-player-investment", "setup-resets-progress"):
            with self.subTest(opponent=opponent):
                result = self.lua.eval("carrier_flow")(str(FIXTURE / "published-4.7/control.lua"),
                                                      str(FIXTURE / "successor/control.lua"), opponent)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(2, result["saves"])
                self.assertEqual(.42, result["player"]["research_progress"])
                self.assertEqual(TAIL, result["player"]["current_research"]["name"])
                self.assertEqual(2, len(list(result["player"]["research_queue"].keys())))

    def test_successor_still_refuses_lost_investment_before_writes(self):
        result = self.lua.eval("carrier_flow")(str(FIXTURE / "published-4.7/control.lua"),
                                              str(FIXTURE / "successor/control.lua"), "lost-successor-progress")
        self.assertFalse(result["ok"])
        self.assertIn("player current queue differs", result["message"])
        self.assertEqual(1, result["saves"])
        state = result["storage"]["mir5_k2se_imersite_carrier_retention"]
        self.assertEqual("source-complete", state["phase"])
        self.assertIsNone(state["destination_mir"])

    def test_successor_refuses_changed_foreign_carrier_before_its_own_state_write(self):
        result = self.lua.eval("carrier_flow")(str(FIXTURE / "published-4.7/control.lua"), str(FIXTURE / "successor/control.lua"), "foreign-enabled")
        self.assertFalse(result["ok"])
        self.assertIn("independently disabled foreign carrier differs", result["message"])
        self.assertEqual(2, len(list(result["markers"].keys())))
        state = result["storage"]["mir5_k2se_imersite_carrier_retention"]
        self.assertEqual("source-complete", state["phase"])
        self.assertIsNone(state["destination_mir"])

    def test_readme_limits_the_fixture_to_native_saved_state_retention(self):
        readme = (FIXTURE / "README.md").read_text(encoding="utf-8")
        for text in (PUBLISHED_SHA, SUCCESSOR_SHA, SUCCESSOR_SOURCE, SUCCESSOR_SOURCE_TREE, f"{SUCCESSOR_BYTES} bytes",
                     "not laboratory-earned historical evidence", "K2SO runtime bridge",
                     "A15 and canonical 2E1", "Native execution remains required"):
            self.assertIn(text, readme)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(K2SEImersiteCarrierFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

"""Host controls for the private F200 positive old-cap continuity fixture.

The controls execute fixture data/control code with a bounded native-shaped
mock.  They do not run Factorio or qualify the published-to-MIR5 save.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import re
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/mir5/fixtures/f200-legacy-cap"
ORACLE = ROOT / "spec/mir5/inventory/modern-f200-470.json"
PUBLISHED_PROFILE = ROOT / "tests/mir5/profiles/f200-legacy-cap-published-4.7-2077.json"
MIR5_PROFILE = ROOT / "tests/mir5/profiles/f200-legacy-cap-mir5-2077.json"
NAME = "mir-fixture-mir5-f200-legacy-cap"
GEAR = "recipe-prod-research_gears-1"
SCIENCE = ("automation-science-pack", "logistic-science-pack",
           "chemical-science-pack", "production-science-pack")


def lua_value(lua, value):
    if isinstance(value, dict):
        return lua.table_from({key: lua_value(lua, item) for key, item in value.items()})
    if isinstance(value, (list, tuple)):
        return lua.table_from([lua_value(lua, item) for item in value])
    return value


def plain(value, seen=None):
    if not hasattr(value, "items"):
        return value
    seen = set() if seen is None else seen
    if id(value) in seen:
        raise AssertionError("cyclic Lua fixture value")
    seen.add(id(value))
    keys = list(value.keys())
    if keys and all(isinstance(key, int) and key > 0 for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        result = [plain(value[index], seen) for index in range(1, len(keys) + 1)]
    else:
        result = {key: plain(item, seen) for key, item in value.items()}
    seen.remove(id(value))
    return result


class F200LegacyCapFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        oracle = json.loads(ORACLE.read_text(encoding="utf-8"))
        row = next(item["row"] for item in oracle["profiles"][0]["published_output"]["data"]["additions"]
                   if item["name"] == GEAR)
        cls.oracle_row = deepcopy(row)
        # The fixture selects the historical 1% setting before data-final.
        cls.oracle_row["effects"][0]["change"] = .01

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
          function legacy_cap_data(path, mir, row)
            local raw={technology={[row.name]=row},["double-setting"]={},["int-setting"]={}}
            raw["double-setting"]["ips-effect-per-level-research_gears"]={default_value=10}
            raw["int-setting"]["ips-max-level-research_gears"]={default_value=0}
            local env={mods={base="2.0.77",["more-infinite-research"]=mir},data={raw=raw}}
            env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
            local chunk,message=loadfile(path,"t",env);assert(chunk,message)
            local ok,result=pcall(chunk)
            return {ok=ok,message=tostring(result),row=row,raw=raw}
          end

          function legacy_cap_parse(path, mir, fixture)
            local callbacks,reads={events={}},{}
            local env={script={active_mods={base="2.0.77",["more-infinite-research"]=mir,["mir-fixture-mir5-f200-legacy-cap"]=fixture},
              on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.changed=f end,
              on_load=function(f)callbacks.load=f end,on_event=function(e,f)callbacks.events[e]=f end},
              defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}}
            env._G=env;setmetatable(env,{__index=function(_,key)
              if key=="game" or key=="storage" or key=="settings"then reads[key]=(reads[key]or 0)+1 end
              return _G[key]
            end})
            local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk)
            return {ok=ok,message=tostring(result),callbacks=callbacks,reads=reads}
          end

          function legacy_cap_flow(source_path, destination_path, opponent)
            local callbacks,markers,saves={events={}},0,0
            local GEAR="recipe-prod-research_gears-1"
            local science={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}
            local function inventory()
              local value={items={}}
              function value.insert(row)value.items[row.name]=(value.items[row.name]or 0)+row.count;return row.count end
              function value.get_item_count(name)return value.items[name]or 0 end
              return value
            end
            local input=inventory()
            local lab={valid=true,energy=0}
            function lab.get_inventory(index)assert(index==1);return input end
            local function tech(name, force)
              return {name=name,valid=true,force=force,level=1,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,
                prototype={max_level=4294967295,visible_when_disabled=false},prerequisites={},research_unit_count=1,research_unit_energy=60,
                research_unit_ingredients={{name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1},{name="chemical-science-pack",amount=1},{name="production-science-pack",amount=1}}}
            end
            local function force(name,index)
              local value={name=name,index=index,valid=true,technologies={},recipes={['iron-gear-wheel']={productivity_bonus=0}},research_queue={},research_progress=0}
              value.technologies[GEAR]=tech(GEAR,value);value.technologies["braking-force-1"]=tech("braking-force-1",value)
              function value.enable_all_prototypes()end
              function value.reset_technology_effects() value.recipes['iron-gear-wheel'].productivity_bonus=0 end
              function value.add_research(research)
                if type(research)=="string"then research=value.technologies[research]end
                if research==nil or value.current_research~=nil then return false end
                value.current_research=research;value.research_queue={research};return true
              end
              return value
            end
            local player,foreign=force("player",1),nil
            local game={tick=0,speed=1,forces={player=player,[1]=player},surfaces={}}
            game.surfaces[1]={create_entity=function(row)assert(row.name=="lab" and row.force==player);return lab end}
            function game.create_force(name)foreign=force(name,2);game.forces[name]=foreign;game.forces[2]=foreign;return foreign end
            function game.server_save(name)assert(name=="mir5-native-complete");saves=saves+1 end
            local storage={}
            local function startup(cap)
              return {startup={
                ["ips-max-level-research_gears"]={value=cap},["ips-effect-per-level-research_gears"]={value=1},
                ["mir-settings-profile-import"]={value=""},
              }}
            end
            local function load_control(path,mir,version,settings_values)
              local c={events={}}
              local env={script={active_mods={base="2.0.77",["more-infinite-research"]=mir,["mir-fixture-mir5-f200-legacy-cap"]=version},
                on_init=function(f)c.init=f end,on_configuration_changed=function(f)c.changed=f end,on_load=function(f)c.load=f end,
                on_event=function(e,f)c.events[e]=f end},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},
                game=game,storage=storage,settings=settings_values,helpers={table_to_json=function(row)assert(row.status=="passed");assert(row.stage=="initial" or row.stage=="reload");return "{}"end},
                log=function(row)assert(row:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "));markers=markers+1 end}
              env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
              local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk)
              return ok and c or nil,tostring(result)
            end
            local function invoke(control, kind, event)
              local callback=kind=="tick" and control.events[1] or (kind=="finished" and control.events[2] or control[kind])
              if type(callback)~="function"then return false,"missing "..kind.." callback"end
              local ok,result=pcall(callback,event);return ok,tostring(result)
            end
            local function tick(control)
              game.tick=game.tick+1;return invoke(control,"tick")
            end
            local function complete_player(control, level, bonus)
              player.current_research=nil;player.research_queue={};player.technologies[GEAR].level=level
              player.technologies[GEAR].researched=false;player.recipes['iron-gear-wheel'].productivity_bonus=bonus
              for _,name in ipairs(science)do input.items[name]=input.items[name]-1 end
              return invoke(control,"finished",{research=player.technologies[GEAR]})
            end
            local source,message=load_control(source_path,"4.7.20002","0.1.0",startup(2));if not source then return {ok=false,message=message}end
            -- The independently observed published on_init owns visibility
            -- before the dependent fixture's init, even below the cap.
            player.technologies[GEAR].visible_when_disabled=true
            player.technologies[GEAR].prototype.visible_when_disabled=true
            local ok,result=invoke(source,"init");if not ok then return {ok=false,message=result}end
            ok,result=complete_player(source,2,.01);if not ok then return {ok=false,message=result}end
            ok,result=tick(source);if not ok then return {ok=false,message=result}end
            ok,result=complete_player(source,3,.02);if not ok then return {ok=false,message=result}end
            player.technologies[GEAR].enabled=false;player.technologies[GEAR].visible_when_disabled=true
            ok,result=tick(source);if not ok then return {ok=false,message=result}end
            -- Two cold-source reload markers; on_load itself must only rebuild local witnesses.
            for _=1,2 do ok,result=invoke(source,"load");if not ok then return {ok=false,message=result}end;ok,result=tick(source);if not ok then return {ok=false,message=result}end end
            local state=storage.mir5_f200_legacy_cap
            if opponent=="stale-enable" then player.technologies[GEAR].enabled=false
            elseif opponent=="native-level" then player.technologies[GEAR].level=2
            elseif opponent=="foreign-queue" then foreign.research_progress=.41
            elseif opponent=="saved-progress" then player.technologies[GEAR].saved_progress=.26
            elseif opponent=="lab-count" then state.actual_lab_completions=1 end
            -- This is the candidate lifecycle result under test, not a fixture write.
            if opponent~="stale-enable" then player.technologies[GEAR].enabled=true;player.technologies[GEAR].visible_when_disabled=true end
            local destination,message=load_control(destination_path,"5.0.20000","0.2.0",startup(40));if not destination then return {ok=false,message=message}end
            -- Native upgrade loads the old fixture state before configuration_changed.
            ok,result=invoke(destination,"load");if not ok then return {ok=false,message=result}end
            ok,result=invoke(destination,"changed");if not ok then return {ok=false,message=result}end
            ok,result=complete_player(destination,4,.03);if not ok then return {ok=false,message=result}end
            if opponent=="duplicate-lab"then state.destination_lab_completions=2 end
            ok,result=tick(destination);if not ok then return {ok=false,message=result}end
            for _=1,2 do ok,result=invoke(destination,"load");if not ok then return {ok=false,message=result}end;ok,result=tick(destination);if not ok then return {ok=false,message=result}end end
            return {ok=true,message="",phase=state.phase,source_labs=state.actual_lab_completions,destination_labs=state.destination_lab_completions,
              player_level=player.technologies[GEAR].level,bonus=player.recipes['iron-gear-wheel'].productivity_bonus,
              player_enabled=player.technologies[GEAR].enabled,player_visible=player.technologies[GEAR].visible_when_disabled,
              foreign_progress=foreign.research_progress,foreign_enabled=foreign.technologies[GEAR].enabled,
              markers=markers,saves=saves}
          end
        ''')

    def row(self):
        return lua_value(self.lua, deepcopy(self.oracle_row))

    def test_profiles_use_base_f200_observer_and_two_explicit_fixture_versions(self):
        for path, mir, version in ((PUBLISHED_PROFILE, "4.7.20002", "0.1.0"),
                                   (MIR5_PROFILE, "5.0.20000", "0.2.0")):
            with self.subTest(profile=path.name):
                profile = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(("f200", "2.0.77"), (profile["target"], profile["engine"]["version"]))
                self.assertEqual(["base", "mir-fixture-mir5-active-mods-observer", "more-infinite-research", NAME],
                                 [item["name"] for item in profile["mods"]])
                self.assertEqual(mir, profile["mods"][2]["version"])
                self.assertEqual(version, profile["mods"][3]["version"])
                self.assertNotIn("space-age", [item["name"] for item in profile["mods"]])
                info = json.loads((FIXTURE / ("published" if version == "0.1.0" else "mir5") / "info.json").read_text())
                self.assertEqual((NAME, version, "2.0"), (info["name"], info["version"], info["factorio_version"]))

    def test_independent_base_oracle_preflight_precedes_the_only_count_time_mutation(self):
        for directory, mir in (("published", "4.7.20002"), ("mir5", "5.0.20000")):
            with self.subTest(directory=directory):
                result = self.lua.eval("legacy_cap_data")(str(FIXTURE / directory / "data-final-fixes.lua"), mir, self.row())
                self.assertTrue(result["ok"], result["message"])
                unit = result["row"]["unit"]
                self.assertIsNone(unit["count"])
                self.assertEqual(("1", 1), (unit["count_formula"], unit["time"]))
                self.assertEqual(.01, result["row"]["effects"][1]["change"])
        bad = self.row()
        bad["effects"][1]["change"] = .02
        result = self.lua.eval("legacy_cap_data")(str(FIXTURE / "published" / "data-final-fixes.lua"), "4.7.20002", bad)
        self.assertFalse(result["ok"])
        self.assertIn("1% fixture-selected effect changed", result["message"])
        self.assertIsNone(result["row"]["unit"]["count"])
        self.assertEqual("8000*2^(L-1)", result["row"]["unit"]["count_formula"])
        self.assertEqual(60, result["row"]["unit"]["time"])

    def test_controls_parse_without_game_or_storage_access_and_never_write_source_player_presentation(self):
        for directory, mir, version in (("published", "4.7.20002", "0.1.0"), ("mir5", "5.0.20000", "0.2.0")):
            with self.subTest(directory=directory):
                result = self.lua.eval("legacy_cap_parse")(str(FIXTURE / directory / "control.lua"), mir, version)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual({}, plain(result["reads"]))
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["events"][1])
                self.assertIsNotNone(result["callbacks"]["events"][2])
        source = (FIXTURE / "published" / "control.lua").read_text(encoding="utf-8")
        self.assertIsNone(re.search(r"(?<![A-Za-z0-9_])gear\.enabled\s*=", source))
        self.assertIsNone(re.search(r"(?<![A-Za-z0-9_])gear\.visible_when_disabled\s*=", source))
        self.assertIn("technology(game.forces.player, GEAR).saved_progress = 0.27", source)
        self.assertIn("state.milestone = \"actual2labs\"", source)
        self.assertIn("await-second-queue", source)
        self.assertNotIn("research_queue_enabled", source)
        for directory in ("published", "mir5"):
            control = (FIXTURE / directory / "control.lua").read_text(encoding="utf-8")
            body = control.split("script.on_load(function()", 1)[1].split("script.on_event(defines.events.on_tick", 1)[0]
            self.assertNotIn("game.", body, f"{directory} on_load touched LuaGameScript")
            self.assertNotRegex(body, r"storage\s*\[.*?\]\s*=", f"{directory} on_load wrote fixture storage")

    def test_two_real_source_labs_restore_positive_cap_then_one_real_successor_lab_and_reload(self):
        result = self.lua.eval("legacy_cap_flow")(str(FIXTURE / "published" / "control.lua"),
                                                   str(FIXTURE / "mir5" / "control.lua"), "")
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual("completed", result["phase"])
        self.assertEqual((2, 1), (result["source_labs"], result["destination_labs"]))
        self.assertEqual((4, .03), (result["player_level"], result["bonus"]))
        self.assertTrue(result["player_enabled"])
        self.assertTrue(result["player_visible"])
        self.assertEqual(.42, result["foreign_progress"])
        self.assertFalse(result["foreign_enabled"])
        self.assertEqual((6, 2), (result["markers"], result["saves"]))

    def test_source_and_successor_continuity_opponents_fail(self):
        opponents = {
            "stale-enable": "MIR5 restored player native gear state differs",
            "native-level": "MIR5 restored player native gear state differs",
            "foreign-queue": "foreign queue or progress changed",
            "saved-progress": "MIR5 restored player saved progress differs",
            "lab-count": "published positive-cap source witness is absent",
            "duplicate-lab": "successor did not finish exactly one further lab level",
        }
        for opponent, phrase in opponents.items():
            with self.subTest(opponent=opponent):
                result = self.lua.eval("legacy_cap_flow")(str(FIXTURE / "published" / "control.lua"),
                                                           str(FIXTURE / "mir5" / "control.lua"), opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(F200LegacyCapFixtureTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

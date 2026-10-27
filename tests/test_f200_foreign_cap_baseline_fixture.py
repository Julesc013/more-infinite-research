"""Host controls for the current-MIR F200 foreign cap-baseline preparation.

The controls use the real pure caps module with native-shaped force doubles.
They prepare a future native route; they do not run Factorio or qualify F200.
"""

from __future__ import annotations

import argparse
from copy import deepcopy
import json
from pathlib import Path
import re
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "f200-foreign-cap-baseline"
ORACLE = ROOT / "spec" / "inventory" / "modern-f200-470.json"
NAME = "mir-fixture-mir5-f200-foreign-cap-baseline"
GEAR = "recipe-prod-research_gears-1"
ENGINE_SHA = "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B"
OBSERVER_SHA = "723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87"
MIR_SHA = "BD1B88D7DE85489207F71C1B080FD61617FAEF9655370BF0332A51579308ECE3"
STAGES = {"source": ("0.1.0", 0), "finite": ("0.2.0", 1), "relaxed": ("0.3.0", 0)}
PROFILES = {
    "source": ROOT / "tests" / "profiles" / "f200-foreign-cap-baseline-source-2077.json",
    "finite": ROOT / "tests" / "profiles" / "f200-foreign-cap-baseline-finite-2077.json",
    "relaxed": ROOT / "tests" / "profiles" / "f200-foreign-cap-baseline-relaxed-2077.json",
}


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


class F200ForeignCapBaselineFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        inventory = json.loads(ORACLE.read_text(encoding="utf-8"))
        row = next(item["row"] for item in inventory["profiles"][0]["published_output"]["data"]["additions"]
                   if item["name"] == GEAR)
        cls.row = deepcopy(row)
        cls.row["effects"][0]["change"] = 0.01

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        source_root = str((ROOT / "source").resolve()).replace("\\", "/")
        self.lua.execute(f'package.path = "{source_root}/?.lua;" .. package.path')
        self.lua.execute(r'''
function f200_foreign_cap_data(settings_path, data_path, settings_alias, data_alias, stage, row, opponent)
  local versions={source="0.1.0",finite="0.2.0",relaxed="0.3.0"}
  local caps={source=0,finite=1,relaxed=0}
  local raw={technology={[row.name]=row},["double-setting"]={
    ["ips-effect-per-level-research_gears"]={default_value=10}},["int-setting"]={
    ["ips-max-level-research_gears"]={default_value=0,minimum_value=0}}}
  local env={mods={base="2.0.77",["more-infinite-research"]="5.0.20000",
    ["mir-fixture-mir5-f200-foreign-cap-baseline"]=versions[stage]},data={raw=raw}}
  env.require=function(name)
    local aliases={
      ["__mir-fixture-mir5-f200-foreign-cap-baseline__/fixture_settings"]=settings_alias,
      ["__mir-fixture-mir5-f200-foreign-cap-baseline__/fixture_data_final"]=data_alias,
    }
    local path=aliases[name];assert(path,"unexpected fixture helper "..tostring(name))
    return assert(loadfile(path,"t",env))()
  end
  env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
  local chunk=assert(loadfile(settings_path,"t",env));local ok,message=pcall(chunk)
  if not ok then return {ok=false,message=tostring(message),raw=raw} end
  local cap=caps[stage]
  if opponent=="wrong-cap" then cap=cap==0 and 1 or 0 end
  local effect=opponent=="wrong-effect-setting" and 2 or 1
  if opponent=="wrong-effect" then row.effects[1].change=.02 end
  env.data={raw={technology={[row.name]=row}}}
  env.settings={startup={ ["ips-max-level-research_gears"]={value=cap},
    ["ips-effect-per-level-research_gears"]={value=effect}}}
  chunk=assert(loadfile(data_path,"t",env));ok,message=pcall(chunk)
  return {ok=ok,message=tostring(message),row=row,raw=raw}
end

function f200_foreign_cap_parse(path, common_path, stage)
  local callbacks,reads={events={}},{game=0,storage=0,settings=0}
  local versions={source="0.1.0",finite="0.2.0",relaxed="0.3.0"}
  local env={script={active_mods={base="2.0.77",["more-infinite-research"]="5.0.20000",
      ["mir-fixture-mir5-f200-foreign-cap-baseline"]=versions[stage]},
      on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.changed=f end,
      on_load=function(f)callbacks.load=f end,on_event=function(e,f)callbacks.events[e]=f end},
    defines={events={on_tick=1}}}
  env.require=function(name)
    assert(name=="__mir-fixture-mir5-f200-foreign-cap-baseline__/fixture_control")
    return assert(loadfile(common_path,"t",env))()
  end
  env._G=env;setmetatable(env,{__index=function(_,key)
    if key=="game" or key=="storage" or key=="settings" then reads[key]=reads[key]+1 end
    return _G[key]
  end})
  local chunk=assert(loadfile(path,"t",env));local ok,message=pcall(chunk)
  return {ok=ok,message=tostring(message),callbacks=callbacks,reads=reads}
end

function f200_foreign_cap_flow(common_path, source_path, finite_path, relaxed_path, caps_path, opponent)
  local GEAR="recipe-prod-research_gears-1";local PROBE="braking-force-1"
  local versions={source="0.1.0",finite="0.2.0",relaxed="0.3.0"}
  local caps_for_stage={source=0,finite=1,relaxed=0}
  local markers,saves={},0
  local function technology(name, force)
    return {name=name,valid=true,force=force,level=1,researched=false,enabled=true,
      visible_when_disabled=false,saved_progress=0,prototype={max_level=4294967295}}
  end
  local function force(name,index)
    local value={name=name,index=index,valid=true,technologies={},recipes={['iron-gear-wheel']={productivity_bonus=0}},
      research_queue={},research_progress=0}
    value.technologies[GEAR]=technology(GEAR,value);value.technologies[PROBE]=technology(PROBE,value)
    function value.enable_all_prototypes() end
    function value.reset_technology_effects()
      value.recipes['iron-gear-wheel'].productivity_bonus=(value.technologies[GEAR].level-1)*.01
    end
    function value.add_research(research)
      if research==nil or value.current_research~=nil then return false end
      value.current_research=research;value.research_queue={research};value.research_progress=0;return true
    end
    return value
  end
  local player=force("player",1);local game={tick=0,forces={player=player,[1]=player}}
  function game.create_force(name)
    local foreign=force(name,2);game.forces[name]=foreign;game.forces[2]=foreign;return foreign
  end
  function game.server_save(name) assert(name=="mir5-native-complete");saves=saves+1 end
  local storage={mir_caps={owned_disabled={}}}
  local pure_env=setmetatable({}, {__index=_G})
  local caps=assert(loadfile(caps_path,"t",pure_env))()
  local function settings(stage)
    return {startup={ ["ips-enable-research_gears"]={value=true},
      ["ips-max-level-research_gears"]={value=caps_for_stage[stage]},
      ["ips-effect-per-level-research_gears"]={value=1},["mir-settings-profile-import"]={value=""}}}
  end
  local function load_control(path, stage)
    local callbacks={events={}}
    local env={game=game,storage=storage,settings=settings(stage),
      script={active_mods={base="2.0.77",["more-infinite-research"]="5.0.20000",
        ["mir-fixture-mir5-f200-foreign-cap-baseline"]=versions[stage]},
        on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.changed=f end,
        on_load=function(f)callbacks.load=f end,on_event=function(e,f)callbacks.events[e]=f end},
      defines={events={on_tick=1}},helpers={table_to_json=function(row)
        assert(row.case=="f200-foreign-cap-baseline" and row.status=="passed")
        markers[#markers+1]=row;return "{}" end},log=function(value)
          assert(value:match("^%[MIR5_NATIVE_FIXTURE%] RESULT ")) end}
    env.require=function(name)
      assert(name=="__mir-fixture-mir5-f200-foreign-cap-baseline__/fixture_control")
      return assert(loadfile(common_path,"t",env))()
    end
    env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
    local chunk=assert(loadfile(path,"t",env));local ok,message=pcall(chunk)
    return ok and callbacks or nil,tostring(message)
  end
  local function invoke(control, name)
    local callback=name=="tick" and control.events[1] or control[name]
    if type(callback)~="function" then return false,"missing "..name.." callback" end
    local ok,message=pcall(callback);return ok,tostring(message)
  end
  local function tick(control) game.tick=game.tick+1;return invoke(control,"tick") end
  local function reload(path, stage)
    local control,message=load_control(path,stage);if not control then return false,message end
    local ok,result=invoke(control,"load");if not ok then return false,result end
    return tick(control)
  end
  local function transition(cap)
    local limits={[GEAR]=cap};local targets={[GEAR]=true}
    local owned=storage.mir_caps.owned_disabled
    caps.reconcile(player,limits,owned,targets)
    caps.reconcile(game.forces[2],limits,owned,targets)
  end
  local source,message=load_control(source_path,"source");if not source then return {ok=false,message=message} end
  local ok,result=invoke(source,"init");if not ok then return {ok=false,message=result} end
  if saves~=0 then return {ok=false,message="create-only seed was counted as a save"} end
  ok,result=tick(source);if not ok then return {ok=false,message=result} end
  for _=1,2 do ok,result=reload(source_path,"source");if not ok then return {ok=false,message=result} end end
  if opponent=="lost-progress" then player.technologies[GEAR].saved_progress=.26 end
  if opponent=="foreign-queue" then game.forces[2].research_progress=.41 end
  if opponent=="wrong-effect" then player.recipes['iron-gear-wheel'].productivity_bonus=.01 end
  local finite_cap=opponent=="wrong-cap" and 0 or 1
  transition(finite_cap)
  if opponent=="foreign-reenabled" then game.forces[2].technologies[GEAR].enabled=true end
  local finite;finite,message=load_control(finite_path,"finite");if not finite then return {ok=false,message=message} end
  ok,result=invoke(finite,"changed");if not ok then return {ok=false,message=result,saves=saves} end
  ok,result=tick(finite);if not ok then return {ok=false,message=result,saves=saves} end
  local saved_phase=storage.mir5_f200_foreign_cap_baseline.phase
  for reload_index=1,2 do
    if opponent=="reload-write" and reload_index==1 then storage.mir5_f200_foreign_cap_baseline.player.saved_progress=.26 end
    ok,result=reload(finite_path,"finite");if not ok then return {ok=false,message=result,saves=saves} end
  end
  if storage.mir5_f200_foreign_cap_baseline.phase~=saved_phase then return {ok=false,message="cold reload wrote fixture phase"} end
  transition(0)
  local relaxed;relaxed,message=load_control(relaxed_path,"relaxed");if not relaxed then return {ok=false,message=message} end
  ok,result=invoke(relaxed,"changed");if not ok then return {ok=false,message=result,saves=saves} end
  ok,result=tick(relaxed);if not ok then return {ok=false,message=result,saves=saves} end
  for _=1,2 do ok,result=reload(relaxed_path,"relaxed");if not ok then return {ok=false,message=result,saves=saves} end end
  local foreign=game.forces[2]
  return {ok=true,saves=saves,markers=markers,storage=storage,
    player={level=player.technologies[GEAR].level,researched=player.technologies[GEAR].researched,
      saved_progress=player.technologies[GEAR].saved_progress,
      bonus=player.recipes['iron-gear-wheel'].productivity_bonus},
    foreign={enabled=foreign.technologies[GEAR].enabled,
      visible_when_disabled=foreign.technologies[GEAR].visible_when_disabled,
      research_progress=foreign.research_progress}}
end
''')

    def data_result(self, stage, opponent=""):
        return plain(self.lua.eval("f200_foreign_cap_data")(
            str(FIXTURE / stage / "settings-updates.lua"), str(FIXTURE / stage / "data-final-fixes.lua"),
            str(FIXTURE / "fixture_settings.lua"), str(FIXTURE / "fixture_data_final.lua"),
            stage, lua_value(self.lua, deepcopy(self.row)), opponent,
        ))

    def flow_result(self, opponent=""):
        return plain(self.lua.eval("f200_foreign_cap_flow")(
            str(FIXTURE / "fixture_control.lua"), str(FIXTURE / "source/control.lua"),
            str(FIXTURE / "finite/control.lua"), str(FIXTURE / "relaxed/control.lua"),
            str(ROOT / "source/runtime/caps.lua"), opponent,
        ))

    def test_current_f200_data_preflight_keeps_the_independent_gear_row_unchanged(self):
        for stage, (_, cap) in STAGES.items():
            with self.subTest(stage=stage):
                result = self.data_result(stage)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual((1, cap), (
                    result["raw"]["double-setting"]["ips-effect-per-level-research_gears"]["default_value"],
                    result["raw"]["int-setting"]["ips-max-level-research_gears"]["default_value"],
                ))
                row = result["row"]
                self.assertEqual((None, "8000*2^(L-1)", 60),
                                 (row["unit"].get("count"), row["unit"]["count_formula"], row["unit"]["time"]))
                self.assertEqual(.01, row["effects"][0]["change"])
        for opponent, phrase in (("wrong-cap", "fixture startup settings differ"),
                                  ("wrong-effect-setting", "fixture startup settings differ"),
                                  ("wrong-effect", "fixture-selected gear effect differs")):
            with self.subTest(opponent=opponent):
                result = self.data_result("finite", opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])

    def test_prepared_profiles_bind_only_f200_current_mir_observer_and_each_tiny_stage(self):
        expected_common = [
            ("base", "2.0.77", True),
            ("mir-fixture-mir5-active-mods-observer", "0.1.0", True),
            ("more-infinite-research", "5.0.20000", True),
        ]
        fixture_hashes = {
            "source": "F37D3628B918E9649967C0F1C7E3B9ACE07C696CB54D00DD30C2B110F8D95CFC",
            "finite": "18EEB497CAF09C1AD4BA0DCB044C633AADB34BADCD1DE3B820E889AE8B25860F",
            "relaxed": "81D15678E0D8BF00EFD987672502289020DDC55F2EB2A2F262F2E6C07D23BA96",
        }
        for stage, (version, _) in STAGES.items():
            with self.subTest(stage=stage):
                profile = json.loads(PROFILES[stage].read_text(encoding="utf-8"))
                self.assertEqual((1, f"mir5-f200-foreign-cap-baseline-{stage}", "f200", "2.0", "Defaults"),
                                 (profile["schema"], profile["kind"], profile["target"],
                                  profile["factorio_line"], profile["settings_mode"]))
                self.assertEqual({"version": "2.0.77", "sha256": ENGINE_SHA}, profile["engine"])
                self.assertEqual(expected_common + [(NAME, version, True)],
                                 [(row["name"], row["version"], row["enabled"]) for row in profile["mods"]])
                self.assertEqual({
                    "mir-fixture-mir5-active-mods-observer_0.1.0.zip": OBSERVER_SHA,
                    "more-infinite-research_5.0.20000.zip": MIR_SHA,
                    f"{NAME}_{version}.zip": fixture_hashes[stage],
                }, profile["archive_sha256"])
                self.assertIn("no native pass", profile["scope"])
                if stage == "source":
                    self.assertNotIn("InputSavePath", profile["scope"])
                else:
                    self.assertIn("InputSavePath/ExpectedInputSaveSha256", profile["scope"])

    def test_wrappers_register_without_parse_time_native_access_and_load_is_read_only(self):
        for stage, (version, _) in STAGES.items():
            with self.subTest(stage=stage):
                raw_result = self.lua.eval("f200_foreign_cap_parse")(
                    str(FIXTURE / stage / "control.lua"), str(FIXTURE / "fixture_control.lua"), stage)
                result = plain(raw_result)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual({"game": 0, "storage": 0, "settings": 0}, result["reads"])
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(raw_result["callbacks"]["events"][1])
                if stage == "source":
                    self.assertIsNotNone(result["callbacks"]["init"])
                else:
                    self.assertIsNotNone(result["callbacks"]["changed"])
        source = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        load_body = source.split("script.on_load(function()", 1)[1].split("script.on_event", 1)[0]
        self.assertNotIn("game.", load_body)
        self.assertNotRegex(load_body, r"storage\s*\[.*?\]\s*=")
        self.assertIn("gear.researched = false\n      gear.level = 3", source)
        self.assertIn("foreign.reset_technology_effects()\n  gear.enabled = false", source)

    def test_current_caps_capture_foreign_false_baseline_then_relax_without_labs(self):
        result = self.flow_result()
        self.assertTrue(result["ok"], result.get("message"))
        self.assertEqual(3, result["saves"])
        self.assertEqual(["initial", "reload", "reload"] * 3,
                         [row["stage"] for row in result["markers"]])
        self.assertEqual([0, 0, 0, 1, 1, 1, 0, 0, 0],
                         [row["witnesses"]["cap"] for row in result["markers"]])
        self.assertTrue(all(row["witnesses"]["actual_lab_completions"] == 0 for row in result["markers"]))
        self.assertEqual((3, False, .27, .02),
                         (result["player"]["level"], result["player"]["researched"],
                          result["player"]["saved_progress"], result["player"]["bonus"]))
        self.assertEqual((False, False, .42),
                         (result["foreign"]["enabled"], result["foreign"]["visible_when_disabled"],
                          result["foreign"]["research_progress"]))
        owned = result["storage"]["mir_caps"]["owned_disabled"]
        self.assertNotIn(1, owned)
        self.assertNotIn(2, owned)
        self.assertEqual("relaxed-complete", result["storage"]["mir5_f200_foreign_cap_baseline"]["phase"])

    def test_transition_refuses_reenablement_drift_wrong_cap_and_reload_writes(self):
        opponents = {
            "foreign-reenabled": "finite foreign disablement changed",
            "lost-progress": "finite player earned gear state differs",
            "foreign-queue": "finite foreign queue or progress differs",
            "wrong-effect": "finite player earned gear state differs",
            "wrong-cap": "finite player owned finite cap is absent",
            "reload-write": "cold reload player saved state differs",
        }
        for opponent, phrase in opponents.items():
            with self.subTest(opponent=opponent):
                result = self.flow_result(opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
                self.assertLessEqual(result.get("saves", 0), 2)

    def test_source_state_is_not_a_create_only_save_and_successors_require_prior_state(self):
        original = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        old = original.replace('state.phase, state.player, state.foreign = stage .. "-complete", player, foreign\n      marker("initial", state, expected)\n      game.server_save(SAVE)',
                               'state.phase, state.player, state.foreign = stage .. "-complete", player, foreign\n      marker("initial", state, expected)', 1)
        self.assertNotEqual(original, old)
        self.assertIn("game.server_save(SAVE)", original)
        self.assertIn('state.phase ~= expected.prior', original)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(F200ForeignCapBaselineFixtureTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

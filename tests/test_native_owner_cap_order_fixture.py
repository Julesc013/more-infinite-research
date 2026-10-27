"""Host controls for the three-stage F210 native-owner cap-order fixture.

The controls execute the fixture's stage code with bounded native-shaped
doubles. They prepare a native scenario only; they do not execute Factorio.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "native-owner-cap-order"
NAME = "mir-fixture-mir5-native-owner-cap-order"
ENGINE_SHA = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"
OBSERVER_SHA = "2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C"
MIR_SHA = "E3A65C08AC7798A66FB1BE30D24307B17C8B366DD901953BDE2A09BD6939C8CE"
STAGES = {
    "canonical": ("0.1.0", 1, ("steel-plate", "casting-steel")),
    "permuted": ("0.2.0", 1, ("casting-steel", "steel-plate")),
    "relaxed": ("0.3.0", 0, ("steel-plate", "casting-steel")),
}
_package_spec = importlib.util.spec_from_file_location("native_owner_cap_order_package", ROOT / "tools" / "package.py")
PACKAGE = importlib.util.module_from_spec(_package_spec)
_package_spec.loader.exec_module(PACKAGE)


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


class NativeOwnerCapOrderFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        source_path = str((ROOT / "source").resolve()).replace("\\", "/")
        self.lua.execute(f'package.path = "{source_path}/?.lua;" .. package.path')
        self.lua.execute(r'''
function cap_order_data(settings_path, data_path, settings_alias, data_alias, stage, opponent)
  local effects={
    {type="change-recipe-productivity",recipe="steel-plate",change=.1},
    {type="change-recipe-productivity",recipe="casting-steel",change=.1},
  }
  if opponent=="missing" then effects[2]=nil end
  if opponent=="duplicate" then effects[2]={type="change-recipe-productivity",recipe="steel-plate",change=.1} end
  if opponent=="wrong-value" then effects[2].change=.11 end
  local settings_raw={ ["int-setting"]={ ["ips-max-level-research_steel"]={default_value=0,minimum_value=0}}}
  local prototype_raw={technology={ ["steel-plate-productivity"]={name="steel-plate-productivity",max_level="infinite",effects=effects}}}
  local expected_cap=stage=="canonical" and 1 or stage=="permuted" and 1 or 0
  local effective_cap=opponent=="wrong-cap" and (expected_cap==0 and 1 or 0) or expected_cap
  local startup_value=setmetatable({}, {__index=function(_,key)
    if key=="value" then return effective_cap end
  end, __newindex=function() error("startup setting is read-only") end})
  local env={mods={base="2.1.23",["elevated-rails"]="2.1.23",quality="2.1.23",recycler="2.1.23",["space-age"]="2.1.23",
    ["more-infinite-research"]="5.0.21000",["mir-fixture-mir5-native-owner-cap-order"]=(stage=="canonical" and "0.1.0" or stage=="permuted" and "0.2.0" or "0.3.0")},data={raw=settings_raw}}
  local cache={}
  env.require=function(name)
    local aliases={
      ["__mir-fixture-mir5-native-owner-cap-order__/fixture_settings"]=settings_alias,
      ["__mir-fixture-mir5-native-owner-cap-order__/fixture_data_final"]=data_alias,
    }
    local path=aliases[name];assert(path,"unexpected fixture module "..tostring(name))
    if cache[name] then return cache[name] end
    local chunk,message=loadfile(path,"t",env);assert(chunk,message);cache[name]=chunk();return cache[name]
  end
  env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
  local chunk,message=loadfile(settings_path,"t",env);assert(chunk,message);local ok,result=pcall(chunk)
  if not ok then return {ok=false,message=tostring(result),raw=settings_raw} end
  local setting=settings_raw["int-setting"]["ips-max-level-research_steel"].default_value
  env.data={raw=prototype_raw}
  env.settings={startup={ ["ips-max-level-research_steel"]=startup_value}}
  chunk,message=loadfile(data_path,"t",env);assert(chunk,message);ok,result=pcall(chunk)
  return {ok=ok,message=tostring(result),raw=prototype_raw,settings_raw=settings_raw,setting=setting}
end

function cap_order_parse(path, control_alias, stage)
  local callbacks,reads={events={}},{game=0,storage=0,settings=0}
  local version=stage=="canonical" and "0.1.0" or stage=="permuted" and "0.2.0" or "0.3.0"
  local env={script={active_mods={base="2.1.23",["elevated-rails"]="2.1.23",quality="2.1.23",recycler="2.1.23",["space-age"]="2.1.23",
      ["more-infinite-research"]="5.0.21000",["mir-fixture-mir5-native-owner-cap-order"]=version},
      on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.changed=f end,
      on_load=function(f)callbacks.load=f end,on_event=function(e,f)callbacks.events[e]=f end},
    defines={events={on_tick=1}}}
  env.require=function(name)
    assert(name=="__mir-fixture-mir5-native-owner-cap-order__/fixture_control")
    local chunk,message=loadfile(control_alias,"t",env);assert(chunk,message);return chunk()
  end
  env._G=env;setmetatable(env,{__index=function(_,key)
    if reads[key]~=nil then reads[key]=reads[key]+1 end
    return _G[key]
  end})
  local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk)
  return {ok=ok,message=tostring(result),callbacks=callbacks,reads=reads}
end

function cap_order_flow(common_path, canonical_path, permuted_path, relaxed_path, opponent)
  local markers,marker_modes,saves,create_saves,resets={}, {},0,0,0
  local effects={{type="change-recipe-productivity",recipe="steel-plate",change=.1},
    {type="change-recipe-productivity",recipe="casting-steel",change=.1}}
  local cap=1
  local function matches(ordered)
    if #effects~=2 then return false end
    if ordered then
      return effects[1].recipe=="steel-plate" and effects[2].recipe=="casting-steel"
        and effects[1].change==.1 and effects[2].change==.1
    end
    local seen={}
    for _,effect in ipairs(effects) do
      if effect.type~="change-recipe-productivity" or effect.change~=.1 or seen[effect.recipe]
          or (effect.recipe~="steel-plate" and effect.recipe~="casting-steel") then return false end
      seen[effect.recipe]=true
    end
    return seen["steel-plate"] and seen["casting-steel"]
  end
  local function make_force(name,index,owned)
    local owner_state={name="steel-plate-productivity",valid=true,level=1,researched=false,enabled=true,visible_when_disabled=false,
      saved_progress=0,prototype={max_level=4294967295,effects=effects}}
    -- LuaTechnology.level re-enables the technology.  A proxy keeps that
    -- setter behavior visible to this fixture's ordinary Lua callbacks.
    local owner=setmetatable({}, {__index=owner_state,__newindex=function(_,key,value)
      owner_state[key]=value
      if key=="level" then owner_state.enabled=true end
    end})
    local probe={name="automation",valid=true,level=1,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,
      prototype={max_level=1,effects={}}}
    local value={name=name,index=index,valid=true,technologies={["steel-plate-productivity"]=owner,automation=probe},
      recipes={ ["steel-plate"]={productivity_bonus=0},["casting-steel"]={productivity_bonus=0}},research_queue={},research_progress=0,owned=owned}
    function value.enable_all_prototypes() end
    function value.reset_technology_effects()
      resets=resets+1
      if value.owned and not matches(opponent=="old-order") then value.owned=false end
      if cap>0 then
        if owner.visible_when_disabled~=true then owner.visible_when_disabled=true;value.visibility_owned=true end
        if value.owned then owner.enabled=false end
      else
        if value.visibility_owned then owner.visible_when_disabled=false;value.visibility_owned=false end
        if value.owned then owner.enabled=true end
      end
      value.recipes["steel-plate"].productivity_bonus=.1
      value.recipes["casting-steel"].productivity_bonus=.1
    end
    function value.add_research(technology)
      if technology==nil or technology.enabled~=true or value.current_research~=nil then return false end
      value.current_research=technology;value.research_queue={technology};value.research_progress=technology.saved_progress or 0
      technology.saved_progress=0;return true
    end
    return value
  end
  local player=make_force("player",1,true)
  local mode="create"
  local game={tick=0,forces={player=player,[1]=player}}
  function game.create_force(name)
    local foreign=make_force(name,2,false);game.forces[name]=foreign;game.forces[2]=foreign;return foreign
  end
  function game.server_save(name)
    assert(name=="mir5-native-complete")
    if mode=="server" then saves=saves+1 else create_saves=create_saves+1 end
  end
  local storage={}
  local function stage_version(stage)
    return stage=="canonical" and "0.1.0" or stage=="permuted" and "0.2.0" or "0.3.0"
  end
  local function load_control(path,stage)
    local callbacks={events={}}
    local env={game=game,storage=storage,settings={startup={
      ["ips-max-level-research_steel"]={value=cap},["mir-settings-profile-import"]={value=""}}},
      helpers={table_to_json=function(row)markers[#markers+1]=row;marker_modes[#marker_modes+1]=mode;return "{}" end},
      log=function(row)assert(row:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "))end,
      script={active_mods={base="2.1.23",["elevated-rails"]="2.1.23",quality="2.1.23",recycler="2.1.23",["space-age"]="2.1.23",
        ["more-infinite-research"]="5.0.21000",["mir-fixture-mir5-native-owner-cap-order"]=stage_version(stage)},
        on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.changed=f end,
        on_load=function(f)callbacks.load=f end,on_event=function(event,f)callbacks.events[event]=f end},defines={events={on_tick=1}}}
    env.require=function(name)
      assert(name=="__mir-fixture-mir5-native-owner-cap-order__/fixture_control")
      local chunk,message=loadfile(common_path,"t",env);assert(chunk,message);return chunk()
    end
    env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
    local chunk,message=loadfile(path,"t",env);assert(chunk,message);chunk();return callbacks
  end
  local function invoke(callback)
    local ok,message=pcall(callback);return ok,tostring(message)
  end
  local function tick(control)
    game.tick=game.tick+1
    return invoke(control.events[1])
  end
  local function first_server_tick(control, configuration)
    mode="server"
    local ok,message=invoke(control.load);if not ok then return false,message end
    if configuration then ok,message=invoke(control.changed);if not ok then return false,message end end
    return tick(control)
  end
  local function reload_twice(control)
    for _=1,2 do
      mode="server"
      local ok,message=invoke(control.load);if not ok then return false,message end
      ok,message=tick(control);if not ok then return false,message end
    end
    return true,""
  end
  local canonical=load_control(canonical_path,"canonical")
  mode="create"
  local ok,message=invoke(canonical.init);if not ok then return {ok=false,message=message,markers=markers,marker_modes=marker_modes,saves=saves,create_saves=create_saves,resets=resets,storage=storage} end
  if opponent=="seed-skip" then
    local permuted=load_control(permuted_path,"permuted")
    ok,message=first_server_tick(permuted,true)
    return {ok=ok,message=message,markers=markers,marker_modes=marker_modes,saves=saves,create_saves=create_saves,resets=resets,storage=storage}
  end
  ok,message=first_server_tick(canonical,false);if not ok then return {ok=false,message=message,markers=markers,marker_modes=marker_modes,saves=saves,create_saves=create_saves,resets=resets,storage=storage} end
  ok,message=reload_twice(canonical);if not ok then return {ok=false,message=message,markers=markers,saves=saves,resets=resets,storage=storage} end
  if saves~=1 or create_saves~=0 then
    return {ok=false,message="canonical server initial save is absent",markers=markers,marker_modes=marker_modes,saves=saves,create_saves=create_saves,resets=resets,storage=storage}
  end
  if opponent=="skipped-transition" then
    cap=0
    local relaxed=load_control(relaxed_path,"relaxed");ok,message=first_server_tick(relaxed,true)
    return {ok=ok,message=message,markers=markers,marker_modes=marker_modes,saves=saves,create_saves=create_saves,resets=resets,storage=storage}
  end
  cap=1;effects[1],effects[2]=effects[2],effects[1]
  if opponent=="wrong-effect" then effects[1].change=.11 end
  player.reset_technology_effects();game.forces[2].reset_technology_effects()
  if opponent=="corrupt-saved" then storage.mir5_native_owner_cap_order.player.saved_progress=.26 end
  local permuted=load_control(permuted_path,"permuted");ok,message=first_server_tick(permuted,true)
  if not ok then return {ok=false,message=message,markers=markers,marker_modes=marker_modes,saves=saves,create_saves=create_saves,resets=resets,storage=storage} end
  ok,message=reload_twice(permuted);if not ok then return {ok=false,message=message,markers=markers,saves=saves,resets=resets,storage=storage} end
  cap=0;effects[1],effects[2]=effects[2],effects[1];player.reset_technology_effects();game.forces[2].reset_technology_effects()
  if opponent=="foreign-enabled" then game.forces[2].technologies["steel-plate-productivity"].enabled=true end
  local relaxed=load_control(relaxed_path,"relaxed");ok,message=first_server_tick(relaxed,true)
  if not ok then return {ok=false,message=message,markers=markers,marker_modes=marker_modes,saves=saves,create_saves=create_saves,resets=resets,storage=storage} end
  ok,message=reload_twice(relaxed)
  return {ok=ok,message=message,markers=markers,marker_modes=marker_modes,saves=saves,create_saves=create_saves,resets=resets,storage=storage,player=player,foreign=game.forces[2]}
end
''')
        self.lua.execute(r'''
function cap_order_actual_foreign_visibility()
  package.loaded["runtime.caps"]=nil
  local caps=require("runtime.caps")
  local name="steel-plate-productivity"
  local technology={name=name,valid=true,level=2,researched=false,enabled=false,visible_when_disabled=false}
  local force={index=48,valid=true,technologies={[name]=technology}}
  local owned={}
  caps.reconcile(force,{[name]=1},owned)
  local at_cap={enabled=technology.enabled,visible=technology.visible_when_disabled,
    disabled=owned[48] and owned[48][name] and owned[48][name].disabled,
    visibility=owned[48] and owned[48][name] and owned[48][name].visible_when_disabled}
  caps.reconcile(force,{[name]=0},owned)
  return {at_cap=at_cap,relaxed={enabled=technology.enabled,visible=technology.visible_when_disabled,
    owner=owned[48]}}
end
''')

    def _data(self, stage: str, opponent: str = ""):
        return self.lua.eval("cap_order_data")(
            str(FIXTURE / stage / "settings-updates.lua"), str(FIXTURE / stage / "data-final-fixes.lua"),
            str(FIXTURE / "fixture_settings.lua"), str(FIXTURE / "fixture_data_final.lua"), stage, opponent)

    def _flow(self, opponent: str = "", control_path: Path = FIXTURE / "fixture_control.lua"):
        return self.lua.eval("cap_order_flow")(
            str(control_path), str(FIXTURE / "canonical" / "control.lua"),
            str(FIXTURE / "permuted" / "control.lua"), str(FIXTURE / "relaxed" / "control.lua"), opponent)

    def test_profiles_prepare_only_the_exact_f210_space_age_stage_closure(self):
        expected = [
            ("base", "2.1.23"), ("elevated-rails", "2.1.23"), ("quality", "2.1.23"),
            ("recycler", "2.1.23"), ("space-age", "2.1.23"),
            ("mir-fixture-mir5-active-mods-observer", "0.1.0"),
            ("more-infinite-research", "5.0.21000"), (NAME, None),
        ]
        for stage, (version, cap, recipes) in STAGES.items():
            with self.subTest(stage=stage):
                profile = json.loads((ROOT / "tests" / "profiles" /
                                      f"native-owner-cap-order-{stage}-space-age-f210.json").read_text(encoding="utf-8"))
                info = json.loads((FIXTURE / stage / "info.json").read_text(encoding="utf-8"))
                self.assertEqual((1, f"mir5-native-owner-cap-order-{stage}", "f210", "2.1", "Defaults"),
                                 (profile["schema"], profile["kind"], profile["target"], profile["factorio_line"], profile["settings_mode"]))
                self.assertEqual(("2.1.23", ENGINE_SHA), (profile["engine"]["version"], profile["engine"]["sha256"]))
                self.assertEqual([(name, version if name != NAME else STAGES[stage][0]) for name, version in expected],
                                 [(row["name"], row["version"]) for row in profile["mods"]])
                self.assertEqual({"mir-fixture-mir5-active-mods-observer_0.1.0.zip",
                                  "more-infinite-research_5.0.21000.zip"}, set(profile["archive_sha256"]))
                self.assertEqual(OBSERVER_SHA, profile["archive_sha256"]["mir-fixture-mir5-active-mods-observer_0.1.0.zip"])
                self.assertEqual(MIR_SHA, profile["archive_sha256"]["more-infinite-research_5.0.21000.zip"])
                self.assertEqual((NAME, version, "2.1"), (info["name"], info["version"], info["factorio_version"]))
                self.assertIn("pending", profile["scope"])
                self.assertIn("b251ae7a", profile["scope"])
                self.assertIn(str(cap), (FIXTURE / "fixture_settings.lua").read_text(encoding="utf-8"))
                self.assertEqual(2, len(recipes))

    def test_data_stages_preflight_before_only_the_permuted_fixture_write(self):
        for stage, (_, cap, recipes) in STAGES.items():
            with self.subTest(stage=stage):
                result = self._data(stage)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(cap, result["setting"])
                self.assertNotIn("int-setting", result["raw"])
                self.assertIn("int-setting", result["settings_raw"])
                effects = result["raw"]["technology"]["steel-plate-productivity"]["effects"]
                self.assertEqual(list(recipes), [effects[index]["recipe"] for index in range(1, 3)])
                self.assertEqual([.1, .1], [effects[index]["change"] for index in range(1, 3)])
        for opponent, phrase in (("missing", "effect count"), ("duplicate", "effect differs"), ("wrong-value", "effect differs")):
            with self.subTest(opponent=opponent):
                result = self._data("permuted", opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
        with self.subTest(opponent="wrong-cap"):
            result = self._data("permuted", "wrong-cap")
            self.assertFalse(result["ok"])
            self.assertIn("steel cap setting differs", result["message"])
            effects = result["raw"]["technology"]["steel-plate-productivity"]["effects"]
            self.assertEqual(["steel-plate", "casting-steel"], [effects[index]["recipe"] for index in range(1, 3)])
        wrong_phase = self.lua.eval("cap_order_data")(
            str(FIXTURE / "permuted" / "settings-updates.lua"), str(FIXTURE / "permuted" / "data-final-fixes.lua"),
            str(FIXTURE / "fixture_settings.lua"), str(FIXTURE / "fixture_data_final.lua"), "canonical", "")
        self.assertFalse(wrong_phase["ok"])
        self.assertIn("fixture stage closure differs", wrong_phase["message"])

    def test_controls_register_without_state_reads_and_on_load_defers_all_game_access(self):
        for stage in STAGES:
            with self.subTest(stage=stage):
                result = self.lua.eval("cap_order_parse")(
                    str(FIXTURE / stage / "control.lua"), str(FIXTURE / "fixture_control.lua"), stage)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual((0, 0, 0), (result["reads"]["game"], result["reads"]["storage"], result["reads"]["settings"]))
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["events"][1])
                result["callbacks"]["load"]()
        source = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        on_load = source.split("script.on_load", 1)[1].split("script.on_event", 1)[0]
        self.assertNotIn("game.", on_load)
        self.assertNotIn("storage[", on_load)

    def test_canonical_permutation_and_cap_relaxation_keep_only_owned_disablement_through_two_reload_ticks_each(self):
        result = self._flow()
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual((3, 6), (result["saves"], result["resets"]))
        self.assertEqual(0, result["create_saves"])
        markers = [plain(result["markers"][index]) for index in range(1, 10)]
        self.assertEqual(["initial", "reload", "reload"] * 3, [marker["stage"] for marker in markers])
        self.assertEqual(["server"] * 9, [result["marker_modes"][index] for index in range(1, 10)])
        self.assertEqual([1, 1, 1, 1, 1, 1, 0, 0, 0], [marker["witnesses"]["cap"] for marker in markers])
        self.assertEqual([0] * 9, [marker["witnesses"]["actual_lab_completions"] for marker in markers])
        self.assertTrue(all(marker["witnesses"]["native_state_seeded"] for marker in markers))
        self.assertEqual((2, .27, True), (result["player"]["technologies"]["steel-plate-productivity"]["level"],
                                          result["player"]["technologies"]["steel-plate-productivity"]["saved_progress"],
                                          result["player"]["technologies"]["steel-plate-productivity"]["enabled"]))
        self.assertEqual((False, False, .42), (result["foreign"]["technologies"]["steel-plate-productivity"]["enabled"],
                                               result["foreign"]["technologies"]["steel-plate-productivity"]["visible_when_disabled"],
                                               result["foreign"]["research_progress"]))
        self.assertEqual("relaxed-complete", result["storage"]["mir5_native_owner_cap_order"]["phase"])

    def test_transition_refuses_effect_drift_skipped_stage_corrupted_saved_state_and_foreign_enablement(self):
        for opponent, phrase in (("wrong-effect", "effect differs"), ("seed-skip", "required prior"), ("skipped-transition", "required prior"),
                                  ("corrupt-saved", "player saved state differs"), ("foreign-enabled", "foreign native state differs"),
                                  ("old-order", "owned cap was not restored")):
            with self.subTest(opponent=opponent):
                result = self._flow(opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
                if opponent not in ("seed-skip", "skipped-transition"):
                    self.assertLessEqual(result["saves"], 2)

    def test_create_only_completion_cannot_substitute_for_the_required_initial_server_save(self):
        original = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        old = original.replace(
            'local state = {phase = "canonical-prepared", player = player_state, foreign = foreign_state,\n'
            '      foreign_index = foreign.index, stage = stage}\n'
            '    storage[KEY] = state',
            'local state = {phase = "canonical-complete", player = player_state, foreign = foreign_state,\n'
            '      foreign_index = foreign.index, stage = stage}\n'
            '    storage[KEY] = state\n'
            '    marker("initial", state, expected)\n'
            '    game.server_save(SAVE)',
            1,
        )
        old = old.replace(
            'state.player, state.foreign, state.phase, state.stage = player, foreign_state, stage .. "-prepared", stage',
            'state.player, state.foreign, state.phase, state.stage = player, foreign_state, stage .. "-complete", stage\n'
            '    marker("initial", state, expected)\n'
            '    game.server_save(SAVE)',
            1,
        )
        self.assertNotEqual(original, old)
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as temporary:
            old_control = Path(temporary) / "fixture_control.lua"
            old_control.write_text(old, encoding="utf-8")
            result = self._flow(control_path=old_control)
        self.assertFalse(result["ok"])
        observations = [(plain(result["markers"][index])["stage"], result["marker_modes"][index])
                        for index in range(1, len(result["markers"]) + 1)]
        self.assertNotIn(("initial", "server"), observations)
        self.assertEqual((0, 1), (result["saves"], result["create_saves"]))
        self.assertIn("canonical server initial save is absent", result["message"])

    def test_technology_level_setter_requires_a_separate_following_foreign_disable_write(self):
        original = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        old_assignment = "owner.level, owner.enabled, owner.visible_when_disabled = 2, false, false"
        self.assertNotIn(old_assignment, original)
        mutated = original.replace(
            "owner.level = 2\n  owner.enabled = false\n  owner.visible_when_disabled = false",
            old_assignment,
            1,
        )
        self.assertNotEqual(original, mutated)
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as temporary:
            old_control = Path(temporary) / "fixture_control.lua"
            old_control.write_text(mutated, encoding="utf-8")
            result = self._flow(control_path=old_control)
        self.assertFalse(result["ok"])
        self.assertIn("foreign native state differs", result["message"])

    def test_actual_caps_helper_records_only_foreign_visibility_then_restores_it_without_enabling(self):
        result = plain(self.lua.eval("cap_order_actual_foreign_visibility")())
        self.assertEqual((False, True, None, False),
                         (result["at_cap"]["enabled"], result["at_cap"]["visible"],
                          result["at_cap"].get("disabled"), result["at_cap"]["visibility"]))
        self.assertEqual((False, False, None),
                         (result["relaxed"]["enabled"], result["relaxed"]["visible"], result["relaxed"].get("owner")))

    def test_readme_states_raw_projection_and_unfrozen_native_limits(self):
        readme = (FIXTURE / "README.md").read_text(encoding="utf-8")
        for text in ("seven-member source projection", "tracked source bytes", "does not create this projection automatically",
                     "canonical leg uses create-only mode", "configuration callback runs during server load", "first server tick",
                     "no state write or save", OBSERVER_SHA, MIR_SHA, "no native"):
            self.assertIn(text, readme)
        shared = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        self.assertIn("reset_technology_effects", shared)
        self.assertNotIn("__more-infinite-research__", shared)
        self.assertNotIn("remote.call", shared)

    def test_each_thin_stage_can_be_projected_into_only_its_selected_archive_members(self):
        expected = {"info.json", "control.lua", "data-final-fixes.lua", "settings-updates.lua",
                    "fixture_control.lua", "fixture_data_final.lua", "fixture_settings.lua"}
        build_root = ROOT / "build"
        build_root.mkdir(exist_ok=True)
        for stage, (version, _, _) in STAGES.items():
            with self.subTest(stage=stage), tempfile.TemporaryDirectory(dir=build_root) as temporary:
                source = Path(temporary) / "projection"
                source.mkdir()
                for name in ("info.json", "control.lua", "data-final-fixes.lua", "settings-updates.lua"):
                    shutil.copyfile(FIXTURE / stage / name, source / name)
                for name, shared in (("fixture_control.lua", "fixture_control.lua"),
                                     ("fixture_data_final.lua", "fixture_data_final.lua"),
                                     ("fixture_settings.lua", "fixture_settings.lua")):
                    shutil.copyfile(FIXTURE / shared, source / name)
                archive = Path(temporary) / f"{NAME}_{version}.zip"
                record = PACKAGE.build(source, archive)
                self.assertIsNone(record["source_commit"])
                self.assertEqual(expected, {row["path"] for row in record["members"]})
                with zipfile.ZipFile(archive) as zip_file:
                    members = {entry.filename for entry in zip_file.infolist() if not entry.is_dir()}
                    self.assertEqual({f"{NAME}_{version}/{name}" for name in expected}, members)
                    self.assertEqual((FIXTURE / stage / "info.json").read_bytes(),
                                     zip_file.read(f"{NAME}_{version}/info.json"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(NativeOwnerCapOrderFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

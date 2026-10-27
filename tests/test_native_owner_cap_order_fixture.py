"""Host controls for the four-stage F210 native-owner cap-order fixture.

The controls execute the fixture's stage code with bounded native-shaped
doubles. They prepare a native scenario only; they do not execute Factorio.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
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
INPUT_REVISION = "09a66acc9c613617f95074f23f3fd9a4aab4765b"
INPUT_RECEIPT = ROOT / "spec/evidence/native-owner-cap-order-pre-disabled-source-inputs-09a66acc9.json"
FROZEN_PACKAGE_TOOL_SHA256 = "00ED00D66BD558554068405C8882419F852FC2F66646088052888D70E25DA61E"
FIXTURE_SHAS = {
    "source": "510626DA637A34BA760DF1D3752CA137E8CC65116A9BD83423FEDC2328A01907",
    "canonical": "C903D4B2AC0A98AF4CC28B8BB737C07B19CAC72BBB27C8E3B5DC9E780069482D",
    "permuted": "DF603E559893BD6DCDE11CCB7AD637A18470457F95EB9476CCB3347B2A0840B7",
    "relaxed": "4B6D90A3A53F946AE349A35F9F76F75FB7226FECF0ED0D9FCED798C9043FD354",
}
STAGES = {
    "source": ("0.0.1", 0, ("steel-plate", "casting-steel")),
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
        (ROOT / "build").mkdir(exist_ok=True)
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
    ["more-infinite-research"]="5.0.21000",["mir-fixture-mir5-native-owner-cap-order"]=(({source="0.0.1",canonical="0.1.0",permuted="0.2.0",relaxed="0.3.0"})[stage])},data={raw=settings_raw}}
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
  local version=({source="0.0.1",canonical="0.1.0",permuted="0.2.0",relaxed="0.3.0"})[stage]
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

function cap_order_flow(common_path,source_path,canonical_path,permuted_path,relaxed_path,opponent)
  local saves,create_saves,resets=0,0,0
  local markers,marker_modes={},{}
  local effects={{type="change-recipe-productivity",recipe="steel-plate",change=.1},
    {type="change-recipe-productivity",recipe="casting-steel",change=.1}}
  local cap=0
  local owned={}
  package.loaded["runtime.caps"]=nil
  local caps=require("runtime.caps")
  local function matches()
    if #effects~=2 then return false end
    if opponent=="old-order" then return effects[1].recipe=="steel-plate" and effects[2].recipe=="casting-steel" end
    local seen={}
    for _,effect in ipairs(effects) do
      if effect.type~="change-recipe-productivity" or effect.change~=.1 or seen[effect.recipe]
          or (effect.recipe~="steel-plate" and effect.recipe~="casting-steel") then return false end
      seen[effect.recipe]=true
    end
    return seen["steel-plate"] and seen["casting-steel"]
  end
  local function reconcile(force)
    if not matches() then owned[force.index]=nil;return end
    caps.reconcile(force,{["steel-plate-productivity"]=cap},owned)
  end
  local function make_force(name,index)
    local value
    local state={name="steel-plate-productivity",valid=true,level=1,researched=false,enabled=true,
      visible_when_disabled=false,saved_progress=0,prototype={max_level=4294967295,effects=effects}}
    local owner=setmetatable({}, {__index=state,__newindex=function(_,key,entry)
      state[key]=entry
      if key=="level" then state.enabled=true;reconcile(value) end
    end})
    local probe={name="automation",valid=true,level=1,researched=false,enabled=true,
      saved_progress=0,prototype={max_level=1,effects={}}}
    local prerequisite={name="automation-science-pack",valid=true,researched=false,enabled=true}
    value={name=name,index=index,valid=true,technologies={[state.name]=owner,automation=probe,
      [prerequisite.name]=prerequisite}, recipes={["steel-plate"]={productivity_bonus=0},
      ["casting-steel"]={productivity_bonus=0}},research_queue={},research_progress=0}
    function value.enable_all_prototypes() for _,row in pairs(value.technologies) do row.enabled=true end end
    function value.reset_technology_effects()
      resets=resets+1
      -- Observed native reset exposes the owner's enabled prototype default
      -- before the synchronous MIR callback; it does not change earned level.
      owner.enabled=true
      reconcile(value)
      for _,recipe in pairs(value.recipes) do recipe.productivity_bonus=.1*(owner.level-1) end
    end
    function value.add_research(technology)
      if not technology or not technology.enabled or value.current_research then return false end
      if technology==probe and (probe.researched or not prerequisite.researched) then return false end
      value.current_research=technology;value.research_queue={technology};value.research_progress=technology.saved_progress or 0
      technology.saved_progress=0;return true
    end
    return value
  end
  local player=make_force("player",1)
  local mode="create"
  local game={tick=0,forces={player=player,[1]=player}}
  function game.create_force(name)
    local force=make_force(name,2);game.forces[name]=force;game.forces[2]=force;return force
  end
  function game.server_save(name)
    assert(name=="mir5-native-complete")
    if mode=="server" then saves=saves+1 else create_saves=create_saves+1 end
  end
  local storage={}
  local function result(ok,message)
    return {ok=ok,message=message,markers=markers,marker_modes=marker_modes,saves=saves,
      create_saves=create_saves,resets=resets,storage=storage,player=player,foreign=game.forces[2]}
  end
  local function load_control(path,stage)
    local callbacks={events={}}
    local env={game=game,storage=storage,settings={startup={
      ["ips-max-level-research_steel"]={value=cap},["mir-settings-profile-import"]={value=""}}},
      helpers={table_to_json=function(row)markers[#markers+1]=row;marker_modes[#marker_modes+1]=mode;return "{}" end},
      log=function(row)assert(row:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "))end,
      script={active_mods={base="2.1.23",["elevated-rails"]="2.1.23",quality="2.1.23",recycler="2.1.23",["space-age"]="2.1.23",
        ["more-infinite-research"]="5.0.21000",["mir-fixture-mir5-native-owner-cap-order"]=
          ({source="0.0.1",canonical="0.1.0",permuted="0.2.0",relaxed="0.3.0"})[stage]},
        on_init=function(fn)callbacks.init=fn end,on_configuration_changed=function(fn)callbacks.changed=fn end,
        on_load=function(fn)callbacks.load=fn end,on_event=function(event,fn)callbacks.events[event]=fn end},
      defines={events={on_tick=1}}}
    env.require=function(name)
      assert(name=="__mir-fixture-mir5-native-owner-cap-order__/fixture_control")
      local chunk,message=loadfile(common_path,"t",env);assert(chunk,message);return chunk()
    end
    env._G=env;setmetatable(env,{__index=_G})
    local chunk,message=loadfile(path,"t",env);assert(chunk,message);chunk();return callbacks
  end
  local function invoke(callback) local ok,message=pcall(callback);return ok,tostring(message) end
  local function tick(control) game.tick=game.tick+1;return invoke(control.events[1]) end
  local function first_tick(control,configuration)
    mode="server"
    local ok,message=invoke(control.load);if not ok then return false,message end
    if configuration then
      reconcile(player);reconcile(game.forces[2])
      -- A refusal opponent must corrupt the state after the real MIR helper;
      -- native re-enablement before it is now the regression being repaired.
      if opponent=="foreign-enabled" and cap==0 then
        game.forces[2].technologies["steel-plate-productivity"].enabled=true
      end
      ok,message=invoke(control.changed);if not ok then return false,message end
    end
    return tick(control)
  end
  local function reload_twice(control)
    for _=1,2 do
      local ok,message=invoke(control.load);if not ok then return false,message end
      ok,message=tick(control);if not ok then return false,message end
    end
    return true,""
  end
  local source=load_control(source_path,"source")
  local ok,message=invoke(source.init);if not ok then return result(false,message) end
  if opponent=="seed-skip" then
    cap=1
    local permuted=load_control(permuted_path,"permuted");ok,message=first_tick(permuted,true);return result(ok,message)
  end
  ok,message=first_tick(source,false);if not ok then return result(false,message) end
  ok,message=reload_twice(source);if not ok then return result(false,message) end
  if saves~=1 or create_saves~=0 then return result(false,"source server initial save is absent") end
  cap=1
  local canonical=load_control(canonical_path,"canonical");ok,message=first_tick(canonical,true)
  if not ok then return result(false,message) end
  ok,message=reload_twice(canonical);if not ok then return result(false,message) end
  if opponent=="skipped-transition" then
    cap=0;local relaxed=load_control(relaxed_path,"relaxed");ok,message=first_tick(relaxed,true);return result(ok,message)
  end
  effects[1],effects[2]=effects[2],effects[1]
  if opponent=="wrong-effect" then effects[1].change=.11 end
  if opponent=="corrupt-saved" then storage.mir5_native_owner_cap_order.player.saved_progress=.26 end
  local permuted=load_control(permuted_path,"permuted");ok,message=first_tick(permuted,true)
  if not ok then return result(false,message) end
  ok,message=reload_twice(permuted);if not ok then return result(false,message) end
  cap=0;effects[1],effects[2]=effects[2],effects[1]
  local relaxed=load_control(relaxed_path,"relaxed");ok,message=first_tick(relaxed,true)
  if not ok then return result(false,message) end
  ok,message=reload_twice(relaxed);return result(ok,message)
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
            str(control_path), str(FIXTURE / "source" / "control.lua"), str(FIXTURE / "canonical" / "control.lua"),
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
                                  "more-infinite-research_5.0.21000.zip", f"{NAME}_{version}.zip"},
                                 set(profile["archive_sha256"]))
                self.assertEqual(OBSERVER_SHA, profile["archive_sha256"]["mir-fixture-mir5-active-mods-observer_0.1.0.zip"])
                self.assertEqual(MIR_SHA, profile["archive_sha256"]["more-infinite-research_5.0.21000.zip"])
                self.assertEqual(FIXTURE_SHAS[stage], profile["archive_sha256"][f"{NAME}_{version}.zip"])
                self.assertEqual((NAME, version, "2.1"), (info["name"], info["version"], info["factorio_version"]))
                self.assertIn("pending", profile["scope"])
                self.assertIn("b251ae7a", profile["scope"])
                self.assertIn(str(cap), (FIXTURE / "fixture_settings.lua").read_text(encoding="utf-8"))
                self.assertEqual(2, len(recipes))

    def test_prepared_inputs_bind_every_raw_git_alias_without_native_or_saved_state_claims(self):
        receipt = json.loads(INPUT_RECEIPT.read_bytes())
        self.assertEqual("MIR5NativeOwnerCapOrderPreDisabledSourcePreparedInputsV1", receipt["kind"])
        self.assertEqual(INPUT_REVISION, receipt["fixture_source_commit"])
        self.assertEqual("cc99ed1e5a9bb9b392ee5431edf03d92e2d135c2", receipt["fixture_source_tree"])
        for field in ("native_execution", "library_mutation", "lab_completion", "release_qualification"):
            self.assertIs(receipt[field], False)
        self.assertIn("pending", receipt["saved_input_hashes"])
        self.assertEqual(list(STAGES), [row["stage"] for row in receipt["stages"]])
        for row in receipt["stages"]:
            stage, version = row["stage"], STAGES[row["stage"]][0]
            self.assertEqual((version, FIXTURE_SHAS[stage]), (row["version"], row["sha256"]))
            self.assertEqual(7, len(row["members"]))
            expected = {name: f"tests/fixtures/native-owner-cap-order/{stage}/{name}"
                        for name in ("info.json", "control.lua", "data-final-fixes.lua", "settings-updates.lua")}
            expected.update({name: f"tests/fixtures/native-owner-cap-order/{name}"
                             for name in ("fixture_control.lua", "fixture_data_final.lua", "fixture_settings.lua")})
            self.assertEqual(expected, {member["path"]: member["source_path"] for member in row["members"]})
            for member in row["members"]:
                raw = subprocess.check_output(["git", "show", INPUT_REVISION + ":" + member["source_path"]], cwd=ROOT)
                self.assertEqual((member["sha256"], member["bytes"]),
                                 (hashlib.sha256(raw).hexdigest().upper(), len(raw)))
        helper = receipt["package_tool"]
        raw_helper = subprocess.check_output(["git", "show", INPUT_REVISION + ":" + helper["path"]], cwd=ROOT)
        self.assertEqual(helper["sha256"], hashlib.sha256(raw_helper).hexdigest().upper())
        self.assertEqual([
            "spec/evidence/native-owner-cap-order-inputs-5a469182.json",
            "spec/evidence/native-owner-cap-order-inputs-0ddeb251.json",
        ], receipt["historical_prepared_inputs"])
        self.assertEqual(FROZEN_PACKAGE_TOOL_SHA256, helper["sha256"])
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            for row in receipt["stages"]:
                with self.subTest(current_helper_stage=row["stage"]):
                    projection = temporary / (row["stage"] + "-projection")
                    projection.mkdir()
                    for member in row["members"]:
                        (projection / member["path"]).write_bytes(subprocess.check_output(
                            ["git", "show", "HEAD:" + member["source_path"]], cwd=ROOT))
                    record = PACKAGE.build(projection, temporary / Path(row["archive"]).name)
                    self.assertEqual((row["sha256"], row["bytes"]),
                                     (record["sha256"].upper(), record["bytes"]))
                    self.assertEqual([{"path": member["path"], "sha256": member["sha256"].lower(),
                                       "bytes": member["bytes"]}
                                      for member in row["members"]], record["members"])

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
        self.assertEqual((4, 2), (result["saves"], result["resets"]))
        self.assertEqual(0, result["create_saves"])
        markers = [plain(result["markers"][index]) for index in range(1, 13)]
        self.assertEqual(["initial", "reload", "reload"] * 4, [marker["stage"] for marker in markers])
        self.assertEqual(["server"] * 12, [result["marker_modes"][index] for index in range(1, 13)])
        self.assertEqual([0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0], [marker["witnesses"]["cap"] for marker in markers])
        self.assertEqual([0] * 12, [marker["witnesses"]["actual_lab_completions"] for marker in markers])
        self.assertTrue(all(marker["witnesses"]["native_state_seeded"] for marker in markers))
        self.assertEqual((2, .27, True), (result["player"]["technologies"]["steel-plate-productivity"]["level"],
                                          result["player"]["technologies"]["steel-plate-productivity"]["saved_progress"],
                                          result["player"]["technologies"]["steel-plate-productivity"]["enabled"]))
        self.assertEqual((False, False, .42), (result["foreign"]["technologies"]["steel-plate-productivity"]["enabled"],
                                               result["foreign"]["technologies"]["steel-plate-productivity"]["visible_when_disabled"],
                                               result["foreign"]["research_progress"]))
        self.assertEqual("relaxed-complete", result["storage"]["mir5_native_owner_cap_order"]["phase"])

    def test_foreign_queue_requires_the_named_native_prerequisite_without_changing_saved_investment(self):
        original = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        old = original.replace("  prerequisite.researched = true\n", "")
        self.assertNotEqual(original, old)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "missing-prerequisite.lua"
            path.write_text(old, encoding="utf-8", newline="\n")
            refused = self._flow(control_path=path)
        self.assertFalse(refused["ok"])
        self.assertIn("could not queue foreign probe", refused["message"])
        self.assertEqual(0, refused["saves"])
        passed = self._flow()
        self.assertTrue(passed["ok"], passed["message"])
        self.assertTrue(passed["foreign"]["technologies"]["automation-science-pack"]["researched"])
        self.assertFalse(passed["foreign"]["technologies"]["automation"]["researched"])
        self.assertEqual(.42, passed["foreign"]["research_progress"])

    def test_transition_refuses_effect_drift_skipped_stage_corrupted_saved_state_and_foreign_enablement(self):
        for opponent, phrase in (("wrong-effect", "effect differs"), ("seed-skip", "required prior"), ("skipped-transition", "required prior"),
                                  ("corrupt-saved", "player saved state differs"), ("foreign-enabled", "foreign native state differs"),
                                  ("old-order", "owned cap was not restored")):
            with self.subTest(opponent=opponent):
                result = self._flow(opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
                if opponent == "foreign-enabled":
                    self.assertIn("enabled=true", result["message"])
                    self.assertIn("maximum=4294967295", result["message"])
                if opponent not in ("seed-skip", "skipped-transition"):
                    self.assertLessEqual(result["saves"], 3)

    def test_create_only_completion_cannot_substitute_for_the_required_initial_server_save(self):
        original = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        old = original.replace(
            'local state = {phase = "source-prepared", player = player_state, foreign = foreign_state,\n'
            '      foreign_index = foreign.index, stage = stage}\n'
            '    storage[KEY] = state',
            'local state = {phase = "source-complete", player = player_state, foreign = foreign_state,\n'
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
        self.assertIn("source server initial save is absent", result["message"])

    def test_foreign_disablement_must_follow_native_reset_in_uncapped_source(self):
        original = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        mutated = original.replace(
            "foreign.reset_technology_effects()\n  owner.enabled = false",
            "owner.enabled = false\n  foreign.reset_technology_effects()", 1)
        self.assertNotEqual(original, mutated)
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as temporary:
            control = Path(temporary) / "fixture_control.lua"
            control.write_text(mutated, encoding="utf-8", newline="\n")
            result = self._flow(control_path=control)
        self.assertFalse(result["ok"])
        self.assertIn("foreign native state differs", result["message"])
        self.assertEqual(0, result["saves"])

    def test_actual_caps_helper_records_only_foreign_visibility_then_restores_it_without_enabling(self):
        result = plain(self.lua.eval("cap_order_actual_foreign_visibility")())
        self.assertEqual((False, True, False, False),
                         (result["at_cap"]["enabled"], result["at_cap"]["visible"],
                          result["at_cap"].get("disabled"), result["at_cap"]["visibility"]))
        self.assertEqual((False, False, None),
                         (result["relaxed"]["enabled"], result["relaxed"]["visible"], result["relaxed"].get("owner")))

    def test_readme_states_raw_projection_and_unfrozen_native_limits(self):
        readme = (FIXTURE / "README.md").read_text(encoding="utf-8")
        for text in ("seven-member source projection", "tracked source bytes", "does not create this projection automatically",
                     "source leg uses create-only mode", "configuration callback runs during server load", "first server tick",
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

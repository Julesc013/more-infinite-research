"""Host controls for the F200 Space Age scripted-effects startup-toggle fixture.

These checks exercise fixture data/control code with bounded native-shaped
mocks.  They do not run Factorio or qualify the three saved native stages.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests" / "mir5" / "fixtures" / "scripted-effects-toggle"
CONTROL = FIXTURE / "control.lua"
NAME = "mir-fixture-mir5-scripted-effects-toggle"
ENGINE_SHA = "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B"
STAGES = {
    "enabled": ("0.1.0", True),
    "disabled": ("0.2.0", False),
    "reenabled": ("0.3.0", True),
}
AGRICULTURE = "recipe-prod-research_agricultural_growth_speed-1"
SPOILAGE = "recipe-prod-research_spoilage_preservation-1"
SCIENCE = {
    AGRICULTURE: [
        "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
        "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
        "cryogenic-science-pack",
    ],
    SPOILAGE: [
        "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
        "production-science-pack", "space-science-pack", "agricultural-science-pack",
        "cryogenic-science-pack",
    ],
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
        raise AssertionError("cyclic Lua fixture result")
    seen.add(id(value))
    keys = list(value.keys())
    if keys and all(isinstance(key, int) and key > 0 for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        result = [plain(value[index], seen) for index in range(1, len(keys) + 1)]
    else:
        result = {key: plain(item, seen) for key, item in value.items()}
    seen.remove(id(value))
    return result


class ScriptedEffectsToggleFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = LuaRuntime(unpack_returned_tuples=True)

    def setUp(self):
        fixture_path = str(FIXTURE.resolve()).replace("\\", "/")
        self.lua.execute(f'package.path = "{fixture_path}/?.lua;" .. package.path')
        self.lua.execute(r'''
function scripted_toggle_row(name, science, formula, seconds, enabled, effect)
  local prerequisites, ingredients = {}, {}
  for index, value in ipairs(science) do
    prerequisites[index] = value
    ingredients[index] = {name=value, amount=1}
  end
  return {type="technology", name=name, level=1, max_level="infinite", upgrade=true, enabled=enabled,
    prerequisites=prerequisites, unit={count_formula=formula, time=seconds, ingredients=ingredients},
    effects={{type="nothing", effect_description={"modifier-description.mir", effect}}}}
end

function scripted_toggle_data(path, common_path, version, enabled, runtime_enabled, opponent)
  local agricultural = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack"}
  local spoilage = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "space-science-pack", "agricultural-science-pack", "cryogenic-science-pack"}
  local raw={technology={
    ["recipe-prod-research_agricultural_growth_speed-1"]=scripted_toggle_row("recipe-prod-research_agricultural_growth_speed-1", agricultural, "40000*1.5^(L-1)", 90, enabled, "1"),
    ["recipe-prod-research_spoilage_preservation-1"]=scripted_toggle_row("recipe-prod-research_spoilage_preservation-1", spoilage, "50000*1.5^(L-1)", 120, enabled, "1")},
    capsule={yumako={spoil_ticks=216000, spoil_result="spoilage"}},
    ["bool-setting"]={
      ["ips-enable-research_agricultural_growth_speed"]={default_value=true},
      ["ips-enable-research_spoilage_preservation"]={default_value=true}}}
  if opponent == "effect" then raw.technology["recipe-prod-research_spoilage_preservation-1"].effects[1].effect_description[2]="2" end
  local env={mods={base="2.0.77",["elevated-rails"]="2.0.77",quality="2.0.77",["space-age"]="2.0.77",
      ["more-infinite-research"]="5.0.20000",["mir-fixture-mir5-active-mods-observer"]="0.1.0",
      ["mir-fixture-mir5-scripted-effects-toggle"]=version},data={raw=raw},
    settings={startup={
      ["ips-enable-research_agricultural_growth_speed"]={value=runtime_enabled},
      ["ips-enable-research_spoilage_preservation"]={value=runtime_enabled}}}}
  local common
  env.require=function(name)
    if name ~= "data-final-common" then error("unexpected fixture module " .. tostring(name)) end
    if common ~= nil then return common end
    local chunk,message=loadfile(common_path,"t",env);assert(chunk,message);common=chunk();return common
  end
  env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
  local update=path:gsub("data%-final%-fixes%.lua$","settings-updates.lua")
  local chunk,message=loadfile(update,"t",env);assert(chunk,message);local ok,result=pcall(chunk)
  if not ok then return {ok=false,message=tostring(result),raw=raw} end
  local defaults={agriculture=raw["bool-setting"]["ips-enable-research_agricultural_growth_speed"].default_value,
    spoilage=raw["bool-setting"]["ips-enable-research_spoilage_preservation"].default_value}
  raw["bool-setting"]=nil -- settings prototypes do not cross into data-final runtime settings.
  chunk,message=loadfile(path,"t",env);assert(chunk,message);ok,result=pcall(chunk)
  return {ok=ok,message=tostring(result),raw=raw,defaults=defaults}
end

function scripted_toggle_parse(path, version)
  local callbacks, reads = {events={}}, {}
  local env={script={active_mods={base="2.0.77",["elevated-rails"]="2.0.77",quality="2.0.77",["space-age"]="2.0.77",
      ["more-infinite-research"]="5.0.20000",["mir-fixture-mir5-active-mods-observer"]="0.1.0",
      ["mir-fixture-mir5-scripted-effects-toggle"]=version},
      on_init=function(f) callbacks.init=f end,on_load=function(f) callbacks.load=f end,
      on_configuration_changed=function(f) callbacks.changed=f end,on_event=function(event,f) callbacks.events[event]=f end},
    defines={events={on_tick=1,on_research_finished=2,on_tower_planted_seed=3},inventory={lab_input=1,agricultural_tower_input=2,chest=3}}}
  env._G=env;setmetatable(env,{__index=function(_,key)
    if key=="game" or key=="storage" or key=="settings" then reads[key]=(reads[key] or 0)+1 end
    return _G[key]
  end})
  local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk)
  return {ok=ok,message=tostring(result),callbacks=callbacks,reads=reads}
end

function scripted_toggle_changed(path, version, enabled, state, modifier)
  local callbacks={events={}}
  local target=function(name, state_enabled)
    return {name=name,valid=true,level=2,researched=false,enabled=state_enabled,research_unit_count=1,research_unit_energy=60}
  end
  local player={name="player",valid=true,technologies={
    ["recipe-prod-research_agricultural_growth_speed-1"]=target("recipe-prod-research_agricultural_growth_speed-1", enabled),
    ["recipe-prod-research_spoilage_preservation-1"]=target("recipe-prod-research_spoilage_preservation-1", enabled)}}
  local env={script={active_mods={base="2.0.77",["elevated-rails"]="2.0.77",quality="2.0.77",["space-age"]="2.0.77",
      ["more-infinite-research"]="5.0.20000",["mir-fixture-mir5-active-mods-observer"]="0.1.0",
      ["mir-fixture-mir5-scripted-effects-toggle"]=version},
      on_init=function(f)callbacks.init=f end,on_load=function(f)callbacks.load=f end,
      on_configuration_changed=function(f)callbacks.changed=f end,on_event=function(event,f)callbacks.events[event]=f end},
    defines={events={on_tick=1,on_research_finished=2,on_tower_planted_seed=3},inventory={lab_input=1}},
    settings={startup={
      ["ips-enable-research_agricultural_growth_speed"]={value=enabled},
      ["ips-enable-research_spoilage_preservation"]={value=enabled}}},
    storage={mir5_scripted_effects_toggle=state},game={forces={player=player},difficulty_settings={spoil_time_modifier=modifier}}}
  env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
  local chunk,message=loadfile(path,"t",env);assert(chunk,message);chunk();local ok,message=pcall(callbacks.changed)
  return {ok=ok,message=tostring(message),state=state}
end

function scripted_toggle_load(path)
  local callbacks,writes={events={}},0
  local state={phase="source-complete",actual_labs=2,expected_modifier=2.02,foreign_queue={progress=.42}}
  local storage=setmetatable({}, {__index=function(_,key)assert(key=="mir5_scripted_effects_toggle");return state end,
    __newindex=function() writes=writes+1;error("on_load wrote fixture state") end})
  local env={script={active_mods={},on_init=function()end,on_load=function(f)callbacks.load=f end,
    on_configuration_changed=function()end,on_event=function(event,f)callbacks.events[event]=f end},storage=storage,
    game=setmetatable({}, {__index=function() error("on_load accessed game") end}),defines={events={on_tick=1,on_research_finished=2,on_tower_planted_seed=3},inventory={}}}
  env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
  local chunk,message=loadfile(path,"t",env);assert(chunk,message);chunk();callbacks.load()
  return {writes=writes,phase=state.phase,labs=state.actual_labs}
end
''')

    def test_profiles_and_variants_pin_the_three_stage_f200_space_age_chain(self):
        expected_mods = [
            ("base", "2.0.77"), ("elevated-rails", "2.0.77"), ("quality", "2.0.77"),
            ("space-age", "2.0.77"), ("mir-fixture-mir5-active-mods-observer", "0.1.0"),
            ("more-infinite-research", "5.0.20000"), (NAME, None),
        ]
        for stage, (version, enabled) in STAGES.items():
            with self.subTest(stage=stage):
                profile = json.loads((ROOT / "tests" / "mir5" / "profiles" /
                                      f"scripted-effects-toggle-{stage}-f200-sa-2077.json").read_text(encoding="utf-8"))
                info = json.loads((FIXTURE / stage / "info.json").read_text(encoding="utf-8"))
                self.assertEqual((profile["target"], profile["factorio_line"], profile["engine"]["version"],
                                  profile["engine"]["sha256"]), ("f200", "2.0", "2.0.77", ENGINE_SHA))
                actual = [(item["name"], item["version"]) for item in profile["mods"]]
                self.assertEqual(actual, [(name, version if name != NAME else STAGES[stage][0])
                                          for name, version in expected_mods])
                self.assertEqual((info["name"], info["version"], info["factorio_version"]), (NAME, version, "2.0"))
                self.assertEqual(info["dependencies"], [
                    "base >= 2.0.77", "space-age >= 2.0.77", "more-infinite-research = 5.0.20000",
                ])
                self.assertEqual(profile["settings_mode"], "Defaults")
                self.assertIn("re-enabled" if stage == "reenabled" else stage, profile["scope"])
                self.assertEqual(enabled, stage != "disabled")

    def test_data_preflights_exact_rows_and_runtime_settings_before_unit_acceleration(self):
        run = self.lua.eval("scripted_toggle_data")
        for stage, (version, enabled) in STAGES.items():
            with self.subTest(stage=stage):
                result = run(str(FIXTURE / stage / "data-final-fixes.lua"), str(FIXTURE / "data-final-common.lua"),
                             version, enabled, enabled, "")
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual((result["defaults"]["agriculture"], result["defaults"]["spoilage"]), (enabled, enabled))
                raw = plain(result["raw"])
                self.assertEqual(raw["capsule"]["yumako"]["spoil_ticks"], 600)
                for name, formula, seconds in ((AGRICULTURE, "40000*1.5^(L-1)", 90),
                                               (SPOILAGE, "50000*1.5^(L-1)", 120)):
                    row = raw["technology"][name]
                    self.assertEqual((row["unit"].get("count"), row["unit"].get("count_formula"), row["unit"]["time"]),
                                     (1, None, 1))
                    self.assertEqual([item["name"] for item in row["unit"]["ingredients"]], SCIENCE[name])
                    self.assertEqual(row["effects"][0]["effect_description"][1], "1")
                    self.assertEqual(row["enabled"] is not False, enabled)

        wrong_setting = run(str(FIXTURE / "disabled" / "data-final-fixes.lua"), str(FIXTURE / "data-final-common.lua"),
                            "0.2.0", False, True, "")
        self.assertFalse(wrong_setting["ok"])
        self.assertIn("toggle runtime setting differs", wrong_setting["message"])
        untouched = plain(wrong_setting["raw"])["technology"][AGRICULTURE]["unit"]
        self.assertEqual((untouched.get("count"), untouched.get("count_formula"), untouched["time"]),
                         (None, "40000*1.5^(L-1)", 90))

        wrong_effect = run(str(FIXTURE / "enabled" / "data-final-fixes.lua"), str(FIXTURE / "data-final-common.lua"),
                           "0.1.0", True, True, "effect")
        self.assertFalse(wrong_effect["ok"])
        self.assertIn("captured scripted effect differs", wrong_effect["message"])
        untouched = plain(wrong_effect["raw"])["technology"][SPOILAGE]["unit"]
        self.assertEqual((untouched.get("count"), untouched.get("count_formula"), untouched["time"]),
                         (None, "50000*1.5^(L-1)", 120))

    def test_control_registration_is_parse_time_only_and_load_is_read_only(self):
        parse = self.lua.eval("scripted_toggle_parse")
        for stage, (version, _) in STAGES.items():
            with self.subTest(stage=stage):
                result = parse(str(CONTROL), version)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(plain(result["reads"]), {})
                self.assertIsNotNone(result["callbacks"]["init"])
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["changed"])
                self.assertEqual(len(plain(result["callbacks"]["events"])), 3)
        loaded = self.lua.eval("scripted_toggle_load")(str(CONTROL))
        self.assertEqual((loaded["writes"], loaded["phase"], loaded["labs"]), (0, "source-complete", 2))

    def test_configuration_setting_and_external_rebase_opponents_fail_before_physical_setup(self):
        run = self.lua.eval("scripted_toggle_changed")
        source = self.lua.table_from({"phase": "source-complete", "actual_labs": 2,
                                      "foreign_queue": {"current": "braking-force-1", "queue": ["braking-force-1"], "progress": .42}})
        wrong_disabled = run(str(CONTROL), "0.2.0", True, source, 2.02)
        self.assertFalse(wrong_disabled["ok"])
        self.assertIn("scripted-effects toggle setting differs for disabled", wrong_disabled["message"])

        disabled = self.lua.table_from({"phase": "disabled-complete", "actual_labs": 2,
                                        "foreign_queue": {"current": "braking-force-1", "queue": ["braking-force-1"], "progress": .42}})
        missing_rebase = run(str(CONTROL), "0.3.0", True, disabled, 3)
        self.assertFalse(missing_rebase["ok"])
        self.assertIn("reenabled stage did not apply retained spoilage level to external baseline", missing_rebase["message"])

    def test_fixture_uses_public_native_witnesses_and_does_not_emulate_runtime_effects(self):
        source = CONTROL.read_text(encoding="utf-8")
        for token in ("force.add_research", "on_research_finished", "on_tower_planted_seed", "spoil_tick",
                      "game.server_save(SAVE)", "foreign.research_progress = .42", "on_load_read_only"):
            with self.subTest(token=token):
                self.assertIn(token, source)
        for forbidden in ("storage.mir", "reset_technology_effects", "game.create_player", "require("):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, source)
        self.assertNotRegex(source, r"(?:event\.plant|state\.plant)\.tick_grown\s*=")
        self.assertIn("state.plant, state.remaining_growth, state.spoiled = nil, nil, false", source)
        self.assertIn("game.difficulty_settings.spoil_time_modifier = 3", source)
        self.assertIn("disabled.  The next configuration callback must observe and rebase it", source)
        self.assertIn("does not qualify removing or re-adding the Space Age mod", (FIXTURE / "README.md").read_text(encoding="utf-8"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(ScriptedEffectsToggleFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)

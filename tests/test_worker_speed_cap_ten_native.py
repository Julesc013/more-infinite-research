"""Pinned Lua controls for the reduced F200/SE worker-speed cap-ten actor.

These controls exercise fixture setup and the real pure cap reconciler with
native-shaped doubles.  They do not start Factorio or qualify a native run.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "worker-speed-cap-ten-native"
SOURCE = FIXTURE / "source"
CAP10 = FIXTURE / "cap10"
LUA_ROOT = ROOT / "source"
WORKER = "worker-robots-speed-6"
CAP = "mir-max-level-worker-robots-speed"
EXPECTED_ACTIVE_COUNT = 20  # Base + 17 direct SE archives + MIR + fixture.


class WorkerSpeedCapTenNativeFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        source_root = LUA_ROOT.as_posix()
        self.lua.execute(f'package.path = "{source_root}/?.lua;" .. package.path')
        self.lua.execute(r'''
local caps = require("runtime.caps")
local KEY = "mir5_worker_speed_cap_ten"
local WORKER = "worker-robots-speed-6"
local PROBE = "automation"
local AUTOMATION_SCIENCE = "automation-science-pack"
local FIXTURE = "mir-fixture-mir5-worker-speed-cap-ten"
local closure = {
  base = "2.0.77", ["more-infinite-research"] = "5.0.20015", ["space-exploration"] = "0.7.57",
  ["aai-containers"] = "0.3.2", ["aai-industry"] = "0.6.16", ["alien-biomes"] = "0.7.4",
  ["alien-biomes-graphics"] = "0.7.1", jetpack = "0.4.17", robot_attrition = "0.6.6",
  ["shield-projector"] = "0.2.2", ["space-exploration-graphics"] = "0.7.5",
  ["space-exploration-graphics-2"] = "0.7.2", ["space-exploration-graphics-3"] = "0.7.2",
  ["space-exploration-graphics-4"] = "0.7.2", ["space-exploration-graphics-5"] = "0.7.3",
  ["space-exploration-menu-simulations"] = "0.7.4", ["space-exploration-postprocess"] = "0.7.5",
  informatron = "0.4.0", ["aai-signal-transmission"] = "0.5.3",
}

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
end

function worker_cap_data(settings_wrapper, data_wrapper, settings_common, data_common, stage, opponent)
  local versions = {source = "0.1.0", cap10 = "0.2.0"}
  local cap = stage == "source" and 0 or 10
  if opponent == "wrong-cap" then cap = cap == 0 and 10 or 0 end
  local worker = {name = WORKER, max_level = "infinite", prerequisites = {"worker-robots-speed-5"},
    unit = {count_formula = "0.6*((2^(L-6))*1000)", time = 60,
      ingredients = {{"automation-science-pack", 1}, {"utility-science-pack", 1}}},
    effects = {{type = "worker-robot-speed", modifier = opponent == "wrong-effect" and .6 or .65}}}
  local raw = {technology = {[WORKER] = worker}, lab = {lab = {name = "lab", inputs = {"automation-science-pack"}}},
    ["int-setting"] = {["mir-max-level-worker-robots-speed"] = {default_value = 0, minimum_value = 0}}}
  local extensions = {}
  local env = {mods = copy(closure), data = {raw = raw, extend = function(_, rows)
      for _, row in ipairs(rows) do extensions[#extensions + 1] = row end end},
    settings = {startup = {["mir-max-level-worker-robots-speed"] = {value = cap}}}}
  env.mods[FIXTURE] = versions[stage]
  local tables = {}; for key, value in pairs(table) do tables[key] = value end
  tables.deepcopy = copy; env.table = tables
  env.require = function(name)
    if name == "__mir-fixture-mir5-worker-speed-cap-ten__/fixture_settings" then
      return assert(loadfile(settings_common, "t", env))()
    end
    assert(name == "__mir-fixture-mir5-worker-speed-cap-ten__/fixture_data_final")
    return assert(loadfile(data_common, "t", env))()
  end
  env._G = env; setmetatable(env, {__index = function(_, key) return _G[key] end})
  local chunk = assert(loadfile(settings_wrapper, "t", env)); local ok, message = pcall(chunk)
  if not ok then return {ok = false, message = tostring(message), raw = raw, extensions = extensions} end
  chunk = assert(loadfile(data_wrapper, "t", env)); ok, message = pcall(chunk)
  return {ok = ok, message = tostring(message), raw = raw, extensions = extensions}
end

local function technology(name, force)
  local value = {name = name, valid = true, force = force, level = 1, researched = false,
    enabled = true, visible_when_disabled = false, saved_progress = 0,
    prototype = {max_level = 4294967295, effects = name == WORKER
      and {{type = "worker-robot-speed", modifier = .65}} or {}, visible_when_disabled = false},
    prerequisites = {}, research_unit_count = 3, research_unit_energy = 60,
    research_unit_ingredients = {{name = "automation-science-pack", amount = 1},
      {name = "utility-science-pack", amount = 1}}}
  if name == WORKER then value.prerequisites["worker-robots-speed-5"] = {name = "worker-robots-speed-5"} end
  return value
end

local function force(name, index)
  local value = {name = name, index = index, valid = true, technologies = {}, _queue = {},
    current_research = nil, research_progress = 0, worker_robots_speed_modifier = 0}
  value.technologies[WORKER] = technology(WORKER, value)
  value.technologies[PROBE] = technology(PROBE, value)
  value.technologies[AUTOMATION_SCIENCE] = technology(AUTOMATION_SCIENCE, value)
  value.technologies["worker-robots-speed-5"] = technology("worker-robots-speed-5", value)
  function value.enable_all_prototypes() end
  function value.reset_technology_effects()
    local worker = value.technologies[WORKER]
    value.worker_robots_speed_modifier = (worker.level - 1) * .65
  end
  function value.add_research(research)
    if type(research) == "string" then research = value.technologies[research] end
    if research == nil or research.enabled ~= true or value.current_research ~= nil then return false end
    if research.name == WORKER and value.technologies["worker-robots-speed-5"].researched ~= true then return false end
    if research.name == PROBE and value.technologies[AUTOMATION_SCIENCE].researched ~= true then return false end
    value.research_queue = {research}; return true
  end
  return setmetatable(value, {__index = function(self, key)
      if key == "research_queue" then return rawget(self, "_queue") end
    end, __newindex = function(self, key, item)
      if key ~= "research_queue" then rawset(self, key, item); return end
      rawset(self, "_queue", item); rawset(self, "current_research", item[1])
      rawset(self, "research_progress", item[1] and 0 or 0)
    end})
end

local function inventory()
  local value = {items = {}, capacity = 200}
  function value.insert(row)
    local accepted = math.min(row.count, math.max(0, value.capacity - (value.items[row.name] or 0)))
    value.items[row.name] = (value.items[row.name] or 0) + accepted
    return accepted
  end
  function value.get_item_count(name) return value.items[name] or 0 end
  return value
end

local function load_control(path, common, stage, game, storage, settings, markers, logs, files)
  local callbacks = {events = {}}
  local versions = {source = "0.1.0", cap10 = "0.2.0"}
  local active = copy(closure); active[FIXTURE] = versions[stage]
  local env = {game = game, storage = storage, settings = settings,
    script = {active_mods = active, on_init = function(f) callbacks.init = f end,
      on_configuration_changed = function(f) callbacks.changed = f end, on_load = function(f) callbacks.load = f end,
      on_event = function(event, f) callbacks.events[event] = f end},
    defines = {events = {on_tick = 1, on_research_finished = 2, on_research_started = 3}, inventory = {lab_input = 1}},
    helpers = {table_to_json = function(row) markers[#markers + 1] = row; return '{"fixture":"host-control"}' end,
      write_file = function(path, body, append)
        files[#files + 1] = {path = path, body = body, append = append}
      end},
    log = function(row) logs[#logs + 1] = row end}
  env.require = function(name)
    assert(name == "__mir-fixture-mir5-worker-speed-cap-ten__/fixture_control")
    return assert(loadfile(common, "t", env))()
  end
  env._G = env; setmetatable(env, {__index = function(_, key) return _G[key] end})
  local chunk = assert(loadfile(path, "t", env)); local ok, message = pcall(chunk)
  return ok and callbacks or nil, tostring(message)
end

local function invoke(callback, event)
  if type(callback) ~= "function" then return false, "missing callback" end
  local ok, message = pcall(callback, event); return ok, tostring(message)
end

function worker_cap_flow(source_path, cap_path, common, opponent)
  local player = force("player", 1)
  local game = {tick = 0, forces = {player = player, [1] = player}, surfaces = {}}
  function game.create_force(name)
    local value = force(name, #game.forces + 1)
    game.forces[name], game.forces[value.index] = value, value
    return value
  end
  local saved, created = 0, 0
  game.surfaces[1] = {create_entity = function(row)
    assert(row.name == "mir-worker-speed-cap-ten-fast-lab" and row.force == player)
    created = created + 1
    local value = {valid = true, disabled_by_script = false, unit_number = created, energy = 0, input = inventory()}
    function value.get_inventory(index) assert(index == 1); return value.input end
    game.lab = value; return value
  end}
  function game.server_save(name) assert(name == "mir5-worker-speed-cap-ten-complete"); saved = saved + 1 end
  local storage, markers, logs, files = {mir_caps = {}}, {}, {}, {}
  local function settings(cap) return {startup = {
    ["mir-max-level-worker-robots-speed"] = {value = cap}, ["mir-settings-profile-import"] = {value = ""}}} end
  local source, message = load_control(source_path, common, "source", game, storage, settings(0), markers, logs, files)
  if not source then return {ok = false, message = message} end
  local ok, result = invoke(source.init)
  if not ok then return {ok = false, message = result} end
  if opponent == "source-administrative" or opponent == "source-ordinary" then
    local administrative = opponent == "source-administrative"
    ok, result = invoke(source.events[2], {research = player.technologies["worker-robots-speed-5"],
      by_script = administrative, tick = game.tick})
    return {ok = ok, message = result, state = storage[KEY]}
  end
  if opponent == "source-tick" then
    local tick_ok, tick_message = invoke(source.events[1])
    return {ok = tick_ok, message = tick_message}
  end
  local state = storage[KEY]
  if type(state) ~= "table" then return {ok = false, message = "source state absent"} end
  if opponent == "missing-prerequisite" then player.technologies["worker-robots-speed-5"].researched = false end
  if opponent ~= "skip-lifecycle" then
    for _, value in ipairs({player, game.forces[state.foreign_index], game.forces[state.earned_index]}) do
      caps.reconcile(value, {[WORKER] = 10}, storage.mir_caps, {[WORKER] = true})
    end
  end
  if opponent == "partial-drift" then player.research_progress = .26 end
  if opponent == "foreign-reenabled" then game.forces[state.foreign_index].technologies[WORKER].enabled = true end
  local cap, cap_message = load_control(cap_path, common, "cap10", game, storage, settings(10), markers, logs, files)
  if not cap then return {ok = false, message = cap_message} end
  ok, result = invoke(cap.changed)
  if not ok then return {ok = false, message = result, markers = markers, logs = logs, saves = saved} end
  local owner = player.technologies[WORKER]
  if opponent == "await-level-eleven-start" then
    owner.level = 11
    ok, result = invoke(cap.events[3], {research = owner, tick = game.tick})
    return {ok = ok, message = result}
  end
  if opponent == "level-ten-resumption" then
    ok, result = invoke(cap.events[3], {research = owner, tick = game.tick})
    if not ok then return {ok = false, message = result} end
  end
  game.tick = game.tick + 1; ok, result = invoke(cap.events[1])
  if not ok then return {ok = false, message = result} end
  -- Model the one ordinary native completion after the fixture's exact feed.
  if opponent == "scripted-completion" then
    ok, result = invoke(cap.events[2], {research = owner, by_script = true, tick = game.tick})
    return {ok = ok, message = result}
  end
  player.research_queue = {}; owner.level = 11; player.worker_robots_speed_modifier = state.player_bonus_before + .65
  for name in pairs(state.lab_feed) do game.lab.input.items[name] = 50 end
  caps.reconcile(player, {[WORKER] = 10}, storage.mir_caps, {[WORKER] = true})
  ok, result = invoke(cap.events[2], {research = owner, by_script = false, tick = game.tick})
  if not ok then return {ok = false, message = result} end
  if opponent == "level-eleven-start" then
    ok, result = invoke(cap.events[3], {research = owner, tick = game.tick})
    if not ok then return {ok = false, message = result} end
  end
  for _ = 1, 3 do
    game.tick = game.tick + 1; ok, result = invoke(cap.events[1])
    if not ok then return {ok = false, message = result} end
  end
  for _ = 1, 2 do
    local cold, cold_message = load_control(cap_path, common, "cap10", game, storage, settings(10), markers, logs, files)
    if not cold then return {ok = false, message = cold_message} end
    ok, result = invoke(cold.load); if not ok then return {ok = false, message = result} end
    game.tick = game.tick + 1; ok, result = invoke(cold.events[1]); if not ok then return {ok = false, message = result} end
  end
  return {ok = true, markers = markers, logs = logs, files = files, saves = saved, labs = created, state = storage[KEY],
    player = player, foreign = game.forces[state.foreign_index], earned = game.forces[state.earned_index]}
end
''')

    def data_result(self, stage: str, opponent: str = ""):
        directory = SOURCE if stage == "source" else CAP10
        return self.lua.eval("worker_cap_data")(
            str(directory / "settings-updates.lua"), str(directory / "data-final-fixes.lua"),
            str(FIXTURE / "fixture_settings.lua"), str(FIXTURE / "fixture_data_final.lua"), stage, opponent)

    def flow_result(self, opponent: str = ""):
        return self.lua.eval("worker_cap_flow")(
            str(SOURCE / "control.lua"), str(CAP10 / "control.lua"), str(FIXTURE / "fixture_control.lua"), opponent)

    def test_metadata_declares_only_the_two_explicit_f200_se_stages(self):
        for directory, version in ((SOURCE, "0.1.0"), (CAP10, "0.2.0")):
            with self.subTest(stage=directory.name):
                info = json.loads((directory / "info.json").read_text(encoding="utf-8"))
                self.assertEqual(("mir-fixture-mir5-worker-speed-cap-ten", version, "2.0"),
                                 (info["name"], info["version"], info["factorio_version"]))
                self.assertEqual(["base = 2.0.77", "space-exploration = 0.7.57",
                                  "more-infinite-research = 5.0.20015"], info["dependencies"])

    def test_data_preflight_retains_actual_worker_contract_and_only_adds_fixture_lab(self):
        for stage, cap in (("source", 0), ("cap10", 10)):
            with self.subTest(stage=stage):
                result = self.data_result(stage)
                self.assertTrue(result["ok"], result["message"])
                worker = result["raw"]["technology"][WORKER]
                self.assertEqual(("infinite", "worker-robot-speed", .65),
                                 (worker["max_level"], worker["effects"][1]["type"], worker["effects"][1]["modifier"]))
                self.assertEqual(("0.6*((2^(L-6))*1000)", 60,
                                  ("automation-science-pack", "utility-science-pack")),
                                 (worker["unit"]["count_formula"], worker["unit"]["time"],
                                  tuple(worker["unit"]["ingredients"][index][1] for index in range(1, 3))))
                self.assertEqual(("automation-science-pack", "utility-science-pack"),
                                 tuple(result["extensions"][1]["inputs"][index] for index in range(1, 3)))
                self.assertEqual(cap, result["raw"]["int-setting"][CAP]["default_value"])
                self.assertEqual(1, len(result["extensions"]))
                self.assertEqual("mir-worker-speed-cap-ten-fast-lab", result["extensions"][1]["name"])
        for opponent, phrase in (("wrong-cap", "worker-speed cap startup differs"),
                                  ("wrong-effect", "SE worker-speed effect differs")):
            with self.subTest(opponent=opponent):
                result = self.data_result("cap10", opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])

    def test_source_is_create_only_and_cap_stage_observes_one_ordinary_completion_then_two_cold_reads(self):
        result = self.flow_result()
        self.assertTrue(result["ok"], result["message"])
        level_ten_resumption = self.flow_result("level-ten-resumption")
        self.assertTrue(level_ten_resumption["ok"], level_ten_resumption["message"])
        self.assertEqual((1, 1), (result["saves"], result["labs"]))
        markers = [result["markers"][index] for index in range(1, len(result["markers"]) + 1)]
        self.assertEqual(["source", "complete", "cold", "cold"], [row["phase"] for row in markers])
        self.assertEqual(4, len(result["logs"]))
        self.assertTrue(result["logs"][1].startswith("[MIR_WORKER_SPEED_CAP_TEN phase=source]"))
        self.assertTrue(all(row["case"] == "f200-se-worker-speed-cap-ten" for row in markers))
        self.assertTrue(all(row["active_mod_count"] == EXPECTED_ACTIVE_COUNT for row in markers))
        self.assertTrue(all(row["per_level_speed_effect"] == .65 for row in markers))
        self.assertEqual("5.0.20015", markers[0]["mods"]["more-infinite-research"])
        self.assertEqual("0.7.57", markers[0]["mods"]["space-exploration"])
        complete = markers[1]
        self.assertEqual((1, 0), (complete["ordinary_native_completion_count"], complete["level_eleven_start_count"]))
        ordinary = complete["ordinary_events"]
        self.assertEqual(1, len(ordinary))
        self.assertEqual((WORKER, False), (ordinary[1]["name"], ordinary[1]["by_script"]))
        self.assertIsInstance(ordinary[1]["tick"], int)
        self.assertEqual((2, 1, 0), (len(markers[0]["player"]["queue"]["queue"]),
                                        len(complete["pre_work"]["player"]["queue"]["queue"]),
                                        len(complete["player"]["queue"]["queue"])))
        self.assertEqual(.27, complete["pre_work"]["player"]["queue"]["progress"])
        self.assertFalse(markers[0]["foreign"]["visible"])
        self.assertTrue(complete["pre_work"]["foreign"]["visible"])
        self.assertFalse(complete["pre_work"]["foreign"]["enabled"])
        self.assertEqual(13, complete["pre_work"]["earned_above_cap"]["level"])
        self.assertEqual(complete["pre_work"]["earned_above_cap"]["bonus"], complete["earned_above_cap"]["bonus"])
        self.assertEqual((False, 2), (complete["level_eleven_queue_attempt"]["accepted"],
                                      complete["post_completion_hold_ticks"]))
        self.assertEqual(complete["post_completion"]["lab"]["input_total"],
                         complete["post_completion"]["end_lab"]["input_total"])
        self.assertGreater(complete["post_completion"]["lab"]["input_total"], 0)
        self.assertEqual(complete["post_completion"]["lab"]["scripted_feed_total"],
                         complete["post_completion"]["end_lab"]["scripted_feed_total"])
        input_by_name = complete["post_completion"]["lab"]["input_by_name"]
        end_input_by_name = complete["post_completion"]["end_lab"]["input_by_name"]
        self.assertEqual({key: input_by_name[key] for key in input_by_name},
                         {key: end_input_by_name[key] for key in end_input_by_name})
        self.assertTrue(all(input_by_name[key] > 0 for key in input_by_name))
        feed_by_name = complete["scripted_lab_feed"]
        self.assertEqual({key: input_by_name[key] for key in input_by_name},
                         {key: input_by_name[key] for key in feed_by_name})
        self.assertTrue(all(feed_by_name[key] > input_by_name[key] for key in feed_by_name))
        self.assertFalse(complete["lab"]["disabled_by_script"])
        self.assertTrue(complete["scripted_setup"]["lab_feed"])
        self.assertEqual((11, False, 0), (result["player"]["technologies"][WORKER]["level"],
                                           result["player"]["technologies"][WORKER]["enabled"],
                                           len(result["player"]["research_queue"])))
        self.assertFalse(result["foreign"]["technologies"][WORKER]["enabled"])
        self.assertFalse(result["earned"]["technologies"][WORKER]["enabled"])
        self.assertEqual(13, result["earned"]["technologies"][WORKER]["level"])
        writes = [result["files"][index] for index in range(1, len(result["files"]) + 1)]
        self.assertEqual(["worker-speed-cap-ten/source.json", "worker-speed-cap-ten/complete.json",
                          "worker-speed-cap-ten/cold.json", "worker-speed-cap-ten/cold.json"],
                         [row["path"] for row in writes])
        self.assertEqual({"worker-speed-cap-ten/source.json", "worker-speed-cap-ten/complete.json",
                          "worker-speed-cap-ten/cold.json"}, {row["path"] for row in writes})
        self.assertTrue(all(row["append"] is False and row["body"] == '{"fixture":"host-control"}\n' for row in writes))

    def test_cap_stage_refuses_without_lifecycle_queue_filtering_or_with_adverse_state_drift(self):
        opponents = {
            "skip-lifecycle": "cap-ten did not retain only current level-ten work",
            "partial-drift": "cap-ten did not retain only current level-ten work",
            "foreign-reenabled": "foreign disabled sentinel differs",
            "missing-prerequisite": "player worker predecessor is not researched",
            "scripted-completion": "scripted completion cannot satisfy ordinary cap-ten work",
            "await-level-eleven-start": "level eleven research started",
            "level-eleven-start": "level eleven research started",
        }
        for opponent, phrase in opponents.items():
            with self.subTest(opponent=opponent):
                result = self.flow_result(opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])

    def test_source_tick_is_rejected_and_cold_code_is_explicitly_read_only(self):
        source_tick = self.flow_result("source-tick")
        self.assertFalse(source_tick["ok"])
        self.assertIn("source create-only stage received an actor tick", source_tick["message"])
        administrative = self.flow_result("source-administrative")
        self.assertTrue(administrative["ok"], administrative["message"])
        self.assertEqual("scripted-prerequisite", administrative["state"]["scripted_administrative_events"][1]["setup_class"])
        source_ordinary = self.flow_result("source-ordinary")
        self.assertFalse(source_ordinary["ok"])
        self.assertIn("source stage observed non-administrative research completion", source_ordinary["message"])
        control = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        on_load = control.split("script.on_load(function()", 1)[1].split("script.on_event(defines.events.on_tick", 1)[0]
        self.assertNotIn("game", on_load)
        self.assertNotIn("storage", on_load)
        self.assertIn('marker("cold", state)', control)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(WorkerSpeedCapTenNativeFixtureTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

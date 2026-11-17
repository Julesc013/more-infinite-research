"""Scenario-actor controls for the empty published11 inherited-worker case.

These execute the actor against a bounded Factorio-shaped Lua world. They do
not claim a native save, configuration callback ordering, laboratory tick, or
cold-load result.
"""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "worker-uninvested-inherited-native"


def load_lua52(runtime_dir: Path):
    sys.path.insert(0, str(runtime_dir))
    from lupa.lua52 import LuaRuntime
    return LuaRuntime


class WorkerUninvestedInheritedNativeFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.LuaRuntime = LUA_RUNTIME

    def world(self, family: str, mode: str, opponent: str | None = None, negative: bool = False):
        lua = self.LuaRuntime(unpack_returned_tuples=True)
        lua.globals().actor_path = (FIXTURE / "control.lua").as_posix()
        source_text = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        if opponent == "old-optics":
            source_text = source_text.replace('"steel-processing"', '"optics"')
        elif opponent == "missing-automation-prereq":
            source_text = source_text.replace(
                'player.technologies["automation-science-pack"].researched = true',
                '-- intentionally omitted by the old-source counterfactual')
        elif opponent == "old-player-queue-enabled":
            source_text = source_text.replace(
                'player.research_queue = {player.technologies.automation, player.technologies.logistics}',
                'player.research_queue_enabled = true\n  player.research_queue = {player.technologies.automation, player.technologies.logistics}')
        elif opponent == "old-lab-queue-enabled":
            source_text = source_text.replace(
                'check(lab_force and lab_force.technologies, "lab force is unavailable")',
                'check(lab_force and lab_force.technologies, "lab force is unavailable")\n  lab_force.research_queue_enabled = true')
        lua.globals().actor_text = (source_text if opponent in {"old-optics", "missing-automation-prereq",
                                                                "old-player-queue-enabled", "old-lab-queue-enabled"}
                                    else "")
        lua.globals().family = family
        lua.globals().mode = mode
        lua.globals().opponent = opponent or ""
        lua.globals().negative = negative
        lua.execute(r'''
          local callbacks, markers, saves, entities = {}, {}, {}, {}
          local base = family == "f200" and "2.0.77" or "2.1.24"
          local source = family == "f200" and "4.7.20003" or "4.7.21003"
          local inherited = family == "f200" and "5.0.20011" or "5.0.21011"
          local candidate = family == "f200" and "5.0.20017" or "5.0.21017"
          local MIR, C4, OWNER, DEBIT = "more-infinite-research", "worker-robots-storage-4",
            "mir-worker-storage-default-4", "mir-worker-storage-head-4"
          local callbacks, markers, saves, entities = {}, {}, {}, {}
          local function technology(name, level)
            return {name=name, level=level or 1, researched=false, enabled=true,
              visible_when_disabled=false, saved_progress=0}
          end
          local function force(name, index)
            local values = {name=name, index=index, technologies={}, worker_robots_storage_bonus=0,
              laboratory_speed_modifier=0}
            local queue, current, progress = {}, nil, 0
            for _, id in ipairs({"automation-science-pack", "automation", "logistics", "steel-processing", "worker-robots-storage-1",
                "worker-robots-storage-2", "worker-robots-storage-3", C4}) do
              local row = technology(id, tonumber(id:match("(%d+)$")) or 1); row.force = values
              values.technologies[id] = row
            end
            setmetatable(values, {__index=function(_, key)
              if key == "research_queue" then return queue end
              if key == "current_research" then return current end
              if key == "research_progress" then return progress end
            end, __newindex=function(_, key, value)
              if key == "research_queue" then
                for _, technology in ipairs(value) do
                  if technology.name == "automation" or technology.name == "logistics"
                    or technology.name == "steel-processing" then
                    assert(values.technologies["automation-science-pack"].researched == true,
                      "research requires automation-science-pack")
                  end
                end
                queue = value; current = queue[1]; progress = current and current.saved_progress or 0
                if current then current.saved_progress = 0 end
              elseif key == "research_progress" then
                progress = value
              else
                error("unsupported LuaForce write " .. tostring(key))
              end
            end})
            return values
          end
          local player, enemy, neutral = force("player", 1), force("enemy", 2), force("neutral", 3)
          local nauvis = {}
          local game = {tick=0, forces={player=player,enemy=enemy,neutral=neutral}, difficulty_settings={technology_price_multiplier=1},
            surfaces={nauvis=nauvis,[1]=nauvis}}
          game.create_force = function(name)
            local next_index = 1; for _ in pairs(game.forces) do next_index = next_index + 1 end
            local result = force(name, next_index)
            if name == "mir-worker-uninvested-lab" then result.worker_robots_storage_bonus = 3 end
            game.forces[name] = result; return result
          end
          game.surfaces.nauvis.create_entity = function(spec)
            local values = {}
            local inventory = {insert=function(row) values[row.name] = (values[row.name] or 0) + row.count; return row.count end,
              get_item_count=function(name) return values[name] or 0 end}
            local entity = {valid=true, unit_number=100 + #entities, name=spec.name, force=spec.force,
              disabled_by_script=true, is_updatable=true, energy=0, get_inventory=function() return inventory end}
            entity.consume_all = function() for name in pairs(values) do values[name] = 0 end end
            entities[#entities + 1] = entity
            return entity
          end
          game.surfaces.nauvis.find_entity = function(name, position)
            assert(type(position) == "table" and position[1] == 0 and position[2] == 0, "unexpected lab lookup position")
            for _, entity in ipairs(entities) do if entity.name == name then return entity end end
          end
          game.get_entity_by_unit_number = function(unit)
            if opponent == "no-unit-number-prototype-flag" then return nil end
            for _, entity in ipairs(entities) do if entity.unit_number == unit then return entity end end
          end
          game.server_save = function(name) saves[#saves + 1] = name end
          local prototype_rows = {}
          for level = 1,3 do
            prototype_rows["worker-robots-storage-"..level] = {effects={{type="worker-robot-storage",modifier=1}}}
          end
          local pending_marker, marker_rows
          local env = {game=game, storage={}, prototypes={technology=prototype_rows}, helpers={table_to_json=function(row)
                pending_marker = row; return "{}" end,
              write_file=function(path) markers[#markers + 1] = path; marker_rows = marker_rows or {}; marker_rows[path] = pending_marker end}, log=function() end,
            defines={inventory={lab_input=1},events={on_research_finished=1,on_tick=2}},
            script={active_mods={base=base,[MIR]=source},on_init=function(fn) callbacks.init=fn end,
              on_configuration_changed=function(fn) callbacks.config=fn end,
              on_event=function(event, fn) callbacks[event]=fn end,on_load=function(fn) callbacks.load=fn end}}
          env._G = env; setmetatable(env, {__index=_G})
          local actor = actor_text ~= "" and assert(load(actor_text, "@control.lua", "t", env))
            or assert(loadfile(actor_path, "t", env))
          actor(); callbacks.init(); game.tick=game.tick+1
          local source_ok, source_error = pcall(callbacks[2])
          if opponent == "old-optics" or opponent == "missing-automation-prereq"
              or opponent == "old-player-queue-enabled" or opponent == "old-lab-queue-enabled" then
            local expected = opponent == "old-optics" and "Base unrelated technologies are unavailable"
              or opponent == "missing-automation-prereq" and "research requires automation-science-pack"
              or "unsupported LuaForce write research_queue_enabled"
            assert(not source_ok and tostring(source_error):find(expected, 1, true))
            actor_result={source_error=tostring(source_error)}; return
          end
          assert(source_ok, tostring(source_error))
          assert(saves[1] == "worker-uninvested-source473")
          env.script.active_mods[MIR] = inherited
          local source_lab = game.forces["mir-worker-uninvested-lab"]
          if opponent == "engine-reset-before-config" then
            source_lab.worker_robots_storage_bonus, source_lab.laboratory_speed_modifier = 3, 0
          elseif opponent == "wrong-engine-bonus" then
            source_lab.worker_robots_storage_bonus, source_lab.laboratory_speed_modifier = 2, 0
          end
          local inherited_ok, inherited_error = pcall(callbacks.config, {mod_startup_settings_changed=false,
            mod_changes={[MIR]={old_version=source,new_version=inherited}}})
          if opponent == "wrong-engine-bonus" then
            assert(not inherited_ok and tostring(inherited_error):find("engine changed scenario-owned lab state before MIR", 1, true))
            assert(#saves == 1); actor_result={source_error=tostring(inherited_error)}; return
          end
          assert(inherited_ok, tostring(inherited_error))
          if opponent == "late-mir-bonus-change" then source_lab.worker_robots_storage_bonus = 8 end
          game.tick=game.tick+1
          local inherited_tick_ok, inherited_tick_error = pcall(callbacks[2])
          if opponent == "late-mir-bonus-change" then
            assert(not inherited_tick_ok and tostring(inherited_tick_error):find("frame number differs at lab-force/bonus", 1, true))
            assert(#saves == 1); actor_result={source_error=tostring(inherited_tick_error)}; return
          end
          assert(inherited_tick_ok, tostring(inherited_tick_error)); assert(saves[2] == "worker-uninvested-inherited11")
          local selected = negative and (family == "f200" and "5.0.20016" or "5.0.21016") or candidate
          env.script.active_mods[MIR] = selected
          local startup = mode == "startup"
          local changes = {[MIR]={old_version=inherited,new_version=selected}}
          if not startup then env.script.active_mods["mir-worker-uninvested-inherited-addition"] = "0.1.0"
            changes["mir-worker-uninvested-inherited-addition"]={old_version=nil,new_version="0.1.0"} end
          if opponent == "candidate-engine-reset-before-config" then
            source_lab.worker_robots_storage_bonus, source_lab.laboratory_speed_modifier = 3, 0
          end
          if opponent == "addition-old-version" then
            changes["mir-worker-uninvested-inherited-addition"].old_version = "0.0.9"
          end
          if opponent == "worker-invested" then player.technologies[C4].researched = true end
          local ok, message = pcall(callbacks.config, {mod_startup_settings_changed=startup,mod_changes=changes})
          if opponent == "addition-old-version" then assert(not ok and tostring(message):find("unexpected configuration row",1,true)); return end
          if opponent == "worker-invested" then
            assert(not ok and tostring(message):find("canonical worker4 has prior work", 1, true))
            actor_result={source_error=tostring(message)}; return
          end
          assert(ok, tostring(message))
          if negative then
            game.tick=game.tick+1; callbacks[2]()
            assert(#saves == 2 and env.storage.mir_worker_uninvested_inherited_native.phase == "candidate-entry")
            actor_result={markers=markers,saves=saves,trigger=env.storage.mir_worker_uninvested_inherited_native.trigger,
              candidate_version=selected}; return
          end
          if opponent == "candidate-late-mir-bonus-loss" then
            source_lab.worker_robots_storage_bonus = 3
          elseif opponent == "candidate-late-mir-speed-loss" then
            source_lab.laboratory_speed_modifier = 0
          end
          local lab = game.forces["mir-worker-uninvested-lab"]
          if opponent == "candidate-lab-missing" then
            entities[1].name = "not-a-lab"
          elseif opponent == "candidate-lab-invalid" then
            entities[1].valid = false
          elseif opponent == "candidate-lab-wrong-force" then
            entities[1].force = player
          elseif opponent == "candidate-lab-enabled" then
            entities[1].disabled_by_script = false
          end
          for _, f in pairs(game.forces) do
            f.technologies[OWNER] = technology(OWNER,4); f.technologies[OWNER].force=f
            f.technologies[DEBIT] = technology(DEBIT,4); f.technologies[DEBIT].force=f; f.technologies[DEBIT].enabled=false
          end
          local tick_ok, tick_message = pcall(callbacks[2])
          if opponent == "candidate-late-mir-bonus-loss" or opponent == "candidate-late-mir-speed-loss" then
            assert(not tick_ok, tostring(tick_message))
            assert(#saves == 2); actor_result={source_error=tostring(tick_message)}; return
          end
          if opponent == "candidate-lab-missing" or opponent == "candidate-lab-invalid"
              or opponent == "candidate-lab-wrong-force" or opponent == "candidate-lab-enabled" then
            local expected = opponent == "candidate-lab-missing" and "saved source lab entity is unavailable"
              or opponent == "candidate-lab-invalid" and "saved source lab entity is invalid"
              or opponent == "candidate-lab-wrong-force" and "saved source lab force differs"
              or "saved source lab disabled-by-script flag differs"
            assert(not tick_ok and tostring(tick_message):find(expected, 1, true), tostring(tick_message))
            assert(#saves == 2); actor_result={source_error=tostring(tick_message), marker_rows=marker_rows}; return
          end
          assert(tick_ok, tostring(tick_message)); assert(lab.current_research.name == OWNER)
          for _=1,7 do
            game.tick=game.tick+1; callbacks[2]()
            for _, entity in ipairs(entities) do entity.consume_all() end
          end
          local owner, debit = lab.technologies[OWNER], lab.technologies[DEBIT]
          owner.level, owner.researched = 5, false; debit.level = 5; lab.technologies[C4].level=5
          lab.worker_robots_storage_bonus = 8.25; lab.research_queue = {}
          callbacks[1]({research=owner,by_script=false})
          game.tick=game.tick+1; callbacks[2]()
          assert(saves[3] == "worker-uninvested-candidate", tostring(saves[3]))
          callbacks.load(); game.tick=game.tick+1; callbacks[2]()
          assert(markers[#markers] == "worker-uninvested/cold.json", tostring(markers[#markers]))
          actor_result={markers=markers,saves=saves,trigger=env.storage.mir_worker_uninvested_inherited_native.trigger,
            ordinary=env.storage.mir_worker_uninvested_inherited_native.ordinary,
            restoration=env.storage.mir_worker_uninvested_inherited_native.restoration,
            restorations=env.storage.mir_worker_uninvested_inherited_native.restoration_history,
            lab_bonus=lab.worker_robots_storage_bonus, marker_rows=marker_rows}
        ''')
        return lua.globals().actor_result

    def test_both_engine_families_cover_startup_and_inert_addition(self):
        for family in ("f200", "f210"):
            for mode, expected in (("startup", "startup-changed"), ("addition", "added-inert")):
                with self.subTest(family=family, mode=mode):
                    result = self.world(family, mode)
                    self.assertEqual(expected, result["trigger"])
                    self.assertEqual(["worker-uninvested-source473", "worker-uninvested-inherited11",
                                      "worker-uninvested-candidate"], list(result["saves"].values()))
                    self.assertTrue(result["ordinary"]["completed"])
                    self.assertFalse(result["ordinary"]["by_script"])
                    self.assertEqual(675, result["ordinary"]["consumed"]["automation-science-pack"])

    def test_added_row_with_an_old_version_refuses_before_candidate_work(self):
        self.world("f210", "addition", "addition-old-version")

    def test_published16_negative_reaches_the_pre_mir_marker_without_actor_work(self):
        for family in ("f200", "f210"):
            for mode, expected in (("startup", "startup-changed"), ("addition", "added-inert")):
                with self.subTest(family=family, mode=mode):
                    result = self.world(family, mode, negative=True)
                    self.assertEqual(expected, result["trigger"])
                    self.assertEqual(2, len(result["saves"]))

    def test_worker_investment_refuses_before_candidate_research(self):
        self.world("f200", "startup", "worker-invested")

    def test_missing_retired_optics_does_not_block_the_source_sentinel(self):
        self.world("f200", "startup")
        result = self.world("f200", "startup", "old-optics")
        self.assertIn("Base unrelated technologies are unavailable", result["source_error"])

    def test_source_queue_requires_the_explicit_base_prerequisite(self):
        self.world("f200", "startup")
        result = self.world("f200", "startup", "missing-automation-prereq")
        self.assertIn("research requires automation-science-pack", result["source_error"])

    def test_source_refuses_the_retired_queue_enabled_force_property(self):
        for opponent in ("old-player-queue-enabled", "old-lab-queue-enabled"):
            with self.subTest(opponent=opponent):
                result = self.world("f200", "startup", opponent)
                self.assertIn("unsupported LuaForce write research_queue_enabled", result["source_error"])

    def test_exact_engine_reset_restores_only_the_scenario_lab_delta(self):
        result = self.world("f200", "startup", "engine-reset-before-config")
        self.assertEqual("restored", result["restorations"]["published11"]["disposition"])
        self.assertEqual(3, result["restorations"]["published11"]["engine_bonus"])
        self.assertEqual(0, result["restorations"]["published11"]["engine_speed"])
        self.assertEqual(8.25, result["lab_bonus"])
        markers = list(result["markers"].values())
        self.assertLess(markers.index("worker-uninvested/engine-before-scenario-restoration.json"),
                        markers.index("worker-uninvested/inherited11-before-configuration.json"))

    def test_unchanged_engine_does_not_reapply_the_scenario_lab_delta(self):
        result = self.world("f210", "startup")
        self.assertEqual("unchanged", result["restoration"]["disposition"])
        self.assertEqual(7.25, result["restoration"]["engine_bonus"])
        self.assertEqual(3600, result["restoration"]["engine_speed"])
        self.assertEqual(8.25, result["lab_bonus"])

    def test_wrong_engine_baseline_and_late_mir_bonus_change_refuse(self):
        for opponent, reason in (("wrong-engine-bonus", "engine changed scenario-owned lab state before MIR"),
                                 ("late-mir-bonus-change", "frame number differs at lab-force/bonus")):
            with self.subTest(opponent=opponent):
                result = self.world("f200", "startup", opponent)
                self.assertIn(reason, result["source_error"])

    def test_candidate_engine_reset_restores_only_the_scenario_lab_delta(self):
        result = self.world("f210", "addition", "candidate-engine-reset-before-config")
        self.assertEqual("candidate", result["restoration"]["stage"])
        self.assertEqual("restored", result["restoration"]["disposition"])
        self.assertEqual(3, result["restoration"]["engine_bonus"])
        self.assertEqual(0, result["restoration"]["engine_speed"])
        self.assertEqual(8.25, result["lab_bonus"])
        markers = list(result["markers"].values())
        self.assertLess(markers.index("worker-uninvested/candidate-engine-before-scenario-restoration.json"),
                        markers.index("worker-uninvested/before-configuration.json"))

    def test_candidate_late_scenario_lab_mutation_refuses_without_a_cold_restore(self):
        for opponent, expected in (
            ("candidate-late-mir-bonus-loss", "frame number differs at lab-force/bonus"),
            ("candidate-late-mir-speed-loss", "frame number differs at lab-force/laboratory_speed"),
        ):
            with self.subTest(opponent=opponent):
                result = self.world("f210", "startup", opponent)
                self.assertIn(expected, result["source_error"])

    def test_candidate_marker_records_the_saved_lab_before_the_ordinary_leg(self):
        result = self.world("f200", "startup")
        frame = result["marker_rows"]["worker-uninvested/candidate-before-ordinary-lab-check.json"]["lab_entity"]
        self.assertTrue(frame["exists"])
        self.assertTrue(frame["valid"])
        self.assertEqual(100, frame["unit_number"])
        self.assertEqual("lab", frame["name"])
        self.assertEqual(4, frame["force"]["index"])
        self.assertEqual("mir-worker-uninvested-lab", frame["force"]["name"])
        self.assertTrue(frame["same_force"])
        self.assertTrue(frame["disabled_by_script"])
        self.assertTrue(frame["is_updatable"])
        self.assertEqual(0, frame["energy"])
        self.assertEqual(0, frame["input_inventory"]["automation-science-pack"])

    def test_standard_lab_lookup_does_not_require_the_unit_number_prototype_flag(self):
        result = self.world("f210", "addition", "no-unit-number-prototype-flag")
        self.assertTrue(result["ordinary"]["completed"])

    def test_candidate_lab_guard_reports_the_actual_retained_entity_fault(self):
        for opponent, expected in (
            ("candidate-lab-missing", "saved source lab entity is unavailable"),
            ("candidate-lab-invalid", "saved source lab entity is invalid"),
            ("candidate-lab-wrong-force", "saved source lab force differs"),
            ("candidate-lab-enabled", "saved source lab disabled-by-script flag differs"),
        ):
            with self.subTest(opponent=opponent):
                result = self.world("f210", "addition", opponent)
                self.assertIn(expected, result["source_error"])
                frame = result["marker_rows"]["worker-uninvested/candidate-before-ordinary-lab-check.json"]["lab_entity"]
                if opponent == "candidate-lab-missing":
                    self.assertFalse(frame["exists"])
                elif opponent == "candidate-lab-invalid":
                    self.assertFalse(frame["valid"])
                elif opponent == "candidate-lab-wrong-force":
                    self.assertEqual("player", frame["force"]["name"])
                    self.assertFalse(frame["same_force"])
                else:
                    self.assertFalse(frame["disabled_by_script"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", required=True)
    arguments, remaining = parser.parse_known_args()
    LUA_RUNTIME = load_lua52(Path(arguments.lua_runtime_dir))
    unittest.main(argv=[sys.argv[0], *remaining])

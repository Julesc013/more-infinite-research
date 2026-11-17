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
        lua.globals().actor_text = (source_text if opponent in {"old-optics", "missing-automation-prereq"}
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
              laboratory_speed_modifier=0, research_queue_enabled=false}
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
                assert(values.research_queue_enabled == true, "research queue is disabled")
                for _, technology in ipairs(value) do
                  if technology.name == "automation" or technology.name == "logistics"
                    or technology.name == "steel-processing" then
                    assert(values.technologies["automation-science-pack"].researched == true,
                      "research requires automation-science-pack")
                  end
                end
                queue = value; current = queue[1]; progress = current and current.saved_progress or 0
                if current then current.saved_progress = 0 end
              elseif key == "research_progress" then progress = value else rawset(values, key, value) end
            end})
            return values
          end
          local player, enemy, neutral = force("player", 1), force("enemy", 2), force("neutral", 3)
          local game = {tick=0, forces={player=player,enemy=enemy,neutral=neutral}, difficulty_settings={technology_price_multiplier=1},
            surfaces={nauvis={}}}
          game.create_force = function(name)
            local next_index = 1; for _ in pairs(game.forces) do next_index = next_index + 1 end
            local result = force(name, next_index); game.forces[name] = result; return result
          end
          game.surfaces.nauvis.create_entity = function(spec)
            local values = {}
            local inventory = {insert=function(row) values[row.name] = (values[row.name] or 0) + row.count; return row.count end,
              get_item_count=function(name) return values[name] or 0 end}
            local entity = {valid=true, unit_number=100 + #entities, force=spec.force, disabled_by_script=true,
              energy=0, get_inventory=function() return inventory end}
            entity.consume_all = function() for name in pairs(values) do values[name] = 0 end end
            entities[#entities + 1] = entity
            return entity
          end
          game.get_entity_by_unit_number = function(unit)
            for _, entity in ipairs(entities) do if entity.unit_number == unit then return entity end end
          end
          game.server_save = function(name) saves[#saves + 1] = name end
          local env = {game=game, storage={}, helpers={table_to_json=function() return "{}" end,
              write_file=function(path) markers[#markers + 1] = path end}, log=function() end,
            defines={inventory={lab_input=1},events={on_research_finished=1,on_tick=2}},
            script={active_mods={base=base,[MIR]=source},on_init=function(fn) callbacks.init=fn end,
              on_configuration_changed=function(fn) callbacks.config=fn end,
              on_event=function(event, fn) callbacks[event]=fn end,on_load=function(fn) callbacks.load=fn end}}
          env._G = env; setmetatable(env, {__index=_G})
          local actor = actor_text ~= "" and assert(load(actor_text, "@control.lua", "t", env))
            or assert(loadfile(actor_path, "t", env))
          actor(); callbacks.init(); game.tick=game.tick+1
          local source_ok, source_error = pcall(callbacks[2])
          if opponent == "old-optics" or opponent == "missing-automation-prereq" then
            local expected = opponent == "old-optics" and "Base unrelated technologies are unavailable"
              or "research requires automation-science-pack"
            assert(not source_ok and tostring(source_error):find(expected, 1, true))
            actor_result={source_error=tostring(source_error)}; return
          end
          assert(source_ok, tostring(source_error))
          assert(saves[1] == "worker-uninvested-source473")
          env.script.active_mods[MIR] = inherited
          callbacks.config({mod_startup_settings_changed=false,
            mod_changes={[MIR]={old_version=source,new_version=inherited}}})
          game.tick=game.tick+1; callbacks[2](); assert(saves[2] == "worker-uninvested-inherited11")
          local selected = negative and (family == "f200" and "5.0.20016" or "5.0.21016") or candidate
          env.script.active_mods[MIR] = selected
          local startup = mode == "startup"
          local changes = {[MIR]={old_version=inherited,new_version=selected}}
          if not startup then env.script.active_mods["mir-worker-uninvested-inherited-addition"] = "0.1.0"
            changes["mir-worker-uninvested-inherited-addition"]={old_version=nil,new_version="0.1.0"} end
          if opponent == "addition-old-version" then
            changes["mir-worker-uninvested-inherited-addition"].old_version = "0.0.9"
          end
          if opponent == "worker-invested" then player.technologies[C4].researched = true end
          local ok, message = pcall(callbacks.config, {mod_startup_settings_changed=startup,mod_changes=changes})
          if opponent == "addition-old-version" then assert(not ok and tostring(message):find("unexpected configuration row",1,true)); return end
          assert(ok, tostring(message))
          if negative then
            game.tick=game.tick+1; callbacks[2]()
            assert(#saves == 2 and env.storage.mir_worker_uninvested_inherited_native.phase == "candidate-entry")
            actor_result={markers=markers,saves=saves,trigger=env.storage.mir_worker_uninvested_inherited_native.trigger,
              candidate_version=selected}; return
          end
          local lab = game.forces["mir-worker-uninvested-lab"]
          for _, f in pairs(game.forces) do
            f.technologies[OWNER] = technology(OWNER,4); f.technologies[OWNER].force=f
            f.technologies[DEBIT] = technology(DEBIT,4); f.technologies[DEBIT].force=f; f.technologies[DEBIT].enabled=false
          end
          local tick_ok, tick_message = pcall(callbacks[2])
          if opponent == "worker-invested" then assert(not tick_ok and tostring(tick_message):find("canonical worker4 has prior work",1,true)); return end
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
            ordinary=env.storage.mir_worker_uninvested_inherited_native.ordinary}
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


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", required=True)
    arguments, remaining = parser.parse_known_args()
    LUA_RUNTIME = load_lua52(Path(arguments.lua_runtime_dir))
    unittest.main(argv=[sys.argv[0], *remaining])

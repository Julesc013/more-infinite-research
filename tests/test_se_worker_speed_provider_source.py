"""Host controls for the explicit SE worker-speed provider source protocol.

These controls exercise a disposable Lua world only.  They neither build an
archive nor establish a native source/admission/upgrade qualification.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import unittest

from se_worker_speed_provider_world import DEEP, FIXTURE, PREDECESSOR, WORKER, install, load_stage, rows

FIXTURE_NAME = "mir-fixture-se-worker-speed-provider-admitted"


class SEWorkerSpeedProviderSourceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        install(self.lua)

    def call(self, name: str, event=None):
        return self.lua.globals().provider_call(name, event)

    def event(self, settings_changed: bool, changes: dict):
        return self.lua.table_from({"mod_startup_settings_changed": settings_changed, "mod_changes": changes}, recursive=True)

    def stage(self, name: str) -> None:
        load_stage(self.lua, name)

    def source(self) -> None:
        self.stage("source")
        ok, message = self.call("init")
        self.assertTrue(ok, message)

    def admitted(self) -> None:
        self.source()
        self.stage("admission")
        event = self.event(False, {FIXTURE_NAME: {"old_version": "0.1.0", "new_version": "0.2.0"}})
        ok, message = self.call("configuration", event)
        self.assertTrue(ok, message)
        ok, message = self.lua.globals().provider_tick(2)
        self.assertTrue(ok, message)

    def candidate_started(self) -> None:
        self.admitted()
        self.lua.globals().provider_candidate_normalize()
        self.stage("candidate")
        event = self.event(True, {FIXTURE_NAME: {"old_version": "0.2.0", "new_version": "0.4.0"},
            "more-infinite-research": {"old_version": "5.0.20015", "new_version": "5.0.20018"}})
        ok, message = self.call("configuration", event)
        self.assertTrue(ok, message)
        ok, message = self.lua.globals().provider_tick(1)
        self.assertTrue(ok, message)

    def test_static_metadata_and_fixed_contract_are_portable(self):
        expected = {
            "source": ("0.1.0", "5.0.20015", 0),
            "admission": ("0.2.0", "5.0.20015", 0),
            "old": ("0.3.0", "5.0.20015", 10),
            "candidate": ("0.4.0", "5.0.20018", 10),
        }
        declared = rows()
        self.assertEqual(196, len(declared))
        self.assertEqual(["se-energy-science-pack-4", "worker-robots-speed-8"], declared[PREDECESSOR])
        self.assertEqual(["se-deep-catalogue-1"], declared[DEEP])
        for stage, (version, mir, cap) in expected.items():
            info = json.loads((FIXTURE / stage / "info.json").read_text(encoding="utf-8"))
            self.assertEqual((version, "2.0"), (info["version"], info["factorio_version"]))
            self.assertIn(f"more-infinite-research = {mir}", info["dependencies"])
            self.assertEqual(cap, 0 if stage in {"source", "admission"} else 10)

    def test_runtime_infinite_uses_uint32_while_data_stage_requires_the_string(self):
        self.source()
        self.setUp()
        self.lua.execute('game.forces.player.technologies["worker-robots-speed-10"].prototype.max_level="infinite"')
        self.stage("source")
        ok, message = self.call("init")
        self.assertFalse(ok)
        self.assertIn("worker target is not infinite", message)
        self.lua.execute('assert(storage.mir5_se_worker_speed_provider_admitted==nil and #markers==0 and #saves==0)')

    def test_runtime_unit_contract_is_level_specific_unordered_and_rejects_uintmax_finite_rows(self):
        self.setUp()
        self.lua.execute(r'''
          local ingredients=game.forces.player.technologies["worker-robots-speed-10"].research_unit_ingredients
          ingredients[1],ingredients[8]=ingredients[8],ingredients[1]
        ''')
        self.source()
        self.lua.execute(r'''
          local player=game.forces.player.technologies["worker-robots-speed-10"]
          local foreign=game.forces["mir5-se-worker-speed-provider-foreign"].technologies["worker-robots-speed-10"]
          local earned=game.forces["mir5-se-worker-speed-provider-earned"].technologies["worker-robots-speed-10"]
          assert(player.research_unit_count==3200 and foreign.research_unit_count==6400 and earned.research_unit_count==25600)
          assert(player.research_unit_energy==3600 and foreign.research_unit_energy==3600 and earned.research_unit_energy==3600)
        ''')

        self.setUp()
        self.lua.execute('game.forces.player.technologies["automation"].prototype.max_level=4294967295')
        self.stage("source")
        ok, message = self.call("init")
        self.assertFalse(ok)
        self.assertIn("finite row differs: automation", message)
        self.lua.execute('assert(storage.mir5_se_worker_speed_provider_admitted==nil and #markers==0 and #saves==0)')

    def test_data_and_settings_wrappers_preserve_the_selected_worker_and_add_only_fixture_rows(self):
        common = (FIXTURE / "fixture_data_final.lua").as_posix()
        settings_common = (FIXTURE / "fixture_settings.lua").as_posix()
        for stage, mir, cap in (("source", "5.0.20015", 0), ("admission", "5.0.20015", 0),
                                ("old", "5.0.20015", 10), ("candidate", "5.0.20018", 10)):
            with self.subTest(stage=stage):
                wrapper = (FIXTURE / stage / "data-final-fixes.lua").as_posix()
                settings_wrapper = (FIXTURE / stage / "settings-updates.lua").as_posix()
                self.lua.globals().data_common = common
                self.lua.globals().settings_common = settings_common
                self.lua.globals().data_wrapper = wrapper
                self.lua.globals().settings_wrapper = settings_wrapper
                self.lua.globals().data_stage = stage
                self.lua.globals().data_mir = mir
                self.lua.globals().data_cap = cap
                self.lua.execute(r'''
                  local worker={name="worker-robots-speed-10",max_level="infinite",prerequisites={
                    ["worker-robots-speed-9"]="worker-robots-speed-9",["se-deep-space-science-pack-1"]="se-deep-space-science-pack-1"},
                    effects={{type="worker-robot-speed",modifier=.65}},unit={count_formula="0.2*(2^(L-6)*1000)",time=60,ingredients={
                      {"automation-science-pack",1},{"logistic-science-pack",1},{"chemical-science-pack",1},{"utility-science-pack",1},
                      {"space-science-pack",1},{"se-rocket-science-pack",1},{"se-energy-science-pack-4",1},{"se-deep-space-science-pack-1",1}}}}
                  local function copy(value)if type(value)~="table"then return value end local out={}for key,item in pairs(value)do out[key]=copy(item)end return out end
                  table.deepcopy=copy;data={raw={technology={ ["worker-robots-speed-10"]=worker,automation={name="automation"}},
                    lab={lab={name="lab",energy_source={type="electric"},researching_speed=1}},["int-setting"]={
                    ["mir-max-level-worker-robots-speed"]={default_value=99,minimum_value=0}}},emitted={}}
                  function data:extend(rows)for _,row in ipairs(rows)do self.emitted[#self.emitted+1]=row end end
                  mods={base="2.0.77",["space-exploration"]="0.7.57",["aai-containers"]="0.3.2",["aai-industry"]="0.6.16",
                    ["alien-biomes"]="0.7.4",["alien-biomes-graphics"]="0.7.1",jetpack="0.4.17",robot_attrition="0.6.6",
                    ["shield-projector"]="0.2.2",["space-exploration-graphics"]="0.7.5",["space-exploration-graphics-2"]="0.7.2",
                    ["space-exploration-graphics-3"]="0.7.2",["space-exploration-graphics-4"]="0.7.2",
                    ["space-exploration-graphics-5"]="0.7.3",["space-exploration-menu-simulations"]="0.7.4",
                    ["space-exploration-postprocess"]="0.7.5",informatron="0.4.0",["aai-signal-transmission"]="0.5.3",
                    ["mir-fixture-se-worker-speed-provider-admitted"]=(data_stage=="source"and"0.1.0"or data_stage=="admission"and"0.2.0"or data_stage=="old"and"0.3.0"or"0.4.0"),
                    ["more-infinite-research"]=data_mir}
                  settings={startup={["mir-max-level-worker-robots-speed"]={value=data_cap}}};logs={};function log(value)logs[#logs+1]=value end
                  require=function(name)
                    if name=="__mir-fixture-se-worker-speed-provider-admitted__/fixture_data_final"then return assert(loadfile(data_common))()end
                    if name=="__mir-fixture-se-worker-speed-provider-admitted__/fixture_settings"then return assert(loadfile(settings_common))()end
                    error("unexpected require "..name)
                  end
                  assert(loadfile(settings_wrapper))();assert(data.raw["int-setting"]["mir-max-level-worker-robots-speed"].default_value==data_cap)
                  assert(loadfile(data_wrapper))();assert(#data.emitted==3 and data.emitted[1].name=="mir-fixture-se-worker-speed-provider-lab")
                  assert(worker.name=="worker-robots-speed-10" and worker.max_level=="infinite" and worker.effects[1].modifier==.65)
                  assert(data.raw.lab.lab.energy_source.type=="electric" and data.raw.lab.lab.researching_speed==1)
                ''')

    def test_source_records_actual_three_force_rows_then_admission_holds_two_ticks_and_saves(self):
        self.admitted()
        self.lua.execute(r'''
          local state=storage.mir5_se_worker_speed_provider_admitted
          assert(state.phase=="admission-saved" and state.provenance.source_mir=="5.0.20015")
          assert(state.source.player.worker.level==10 and state.source.player.current=="worker-robots-speed-10")
          assert(#state.source.player.queue==2 and state.source.player.queue[1]=="worker-robots-speed-10"
            and state.source.player.queue[2]=="worker-robots-speed-10" and state.source.player.worker.saved==0)
          assert(state.source.foreign.current=="mir-fixture-se-worker-speed-provider-unrelated"
            and #state.source.foreign.queue==2 and state.source.foreign.progress==.42
            and state.source.foreign.worker.level==11 and state.source.foreign.worker.enabled==false
            and state.source.foreign.worker.saved==0)
          assert(state.source.earned.worker.level==13 and state.source.earned.worker.enabled==true
            and state.source.earned.worker.saved==0 and state.source.earned.current==false)
          for _,role in ipairs({"player","foreign","earned"})do
            local completed=state.source.completed[role]
            assert(#completed.order==196 and completed.rows["worker-robots-speed-9"].researched==true
              and completed.rows["se-deep-space-science-pack-1"].researched==true)
          end
          assert(state.admission.ticks==2 and #saves==1 and saves[1]=="se-worker-speed-provider-admission")
          assert(markers[1].phase=="source" and markers[2].phase=="admission-pre-hold" and markers[3].phase=="admission-saved")
        ''')

    def test_admission_and_candidate_colds_are_read_only(self):
        self.admitted()
        self.stage("admission")
        self.lua.execute(r'''
          local function copy(v)if type(v)~="table"then return v end local o={}for k,x in pairs(v)do o[k]=copy(x)end return o end
          local function same(a,b)if type(a)~=type(b)then return false end;if type(a)~="table"then return a==b end
            for k,v in pairs(a)do if not same(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
          before_admission_cold=copy(storage)
          assert(provider_call("load"));assert(provider_tick(1));assert(same(before_admission_cold,storage))
        ''')
        self.setUp()
        self.candidate_started()
        ok, message = self.lua.globals().provider_finish(False)
        self.assertTrue(ok, message)
        ok, message = self.lua.globals().provider_tick(2)
        self.assertTrue(ok, message)
        self.stage("candidate")
        self.lua.execute(r'''
          local function copy(v)if type(v)~="table"then return v end local o={}for k,x in pairs(v)do o[k]=copy(x)end return o end
          local function same(a,b)if type(a)~=type(b)then return false end;if type(a)~="table"then return a==b end
            for k,v in pairs(a)do if not same(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
          before_candidate_cold=copy(storage)
          assert(provider_call("load"));assert(provider_tick(1));assert(same(before_candidate_cold,storage))
        ''')

    def test_load_then_configuration_clears_local_cold_pending_for_both_admitted_roles(self):
        self.source()
        self.stage("admission")
        self.assertTrue(self.call("load")[0])
        event = self.event(False, {FIXTURE_NAME: {"old_version": "0.1.0", "new_version": "0.2.0"}})
        self.assertTrue(self.call("configuration", event)[0])
        self.assertTrue(self.lua.globals().provider_tick(1)[0])
        self.lua.execute('assert(storage.mir5_se_worker_speed_provider_admitted.phase=="admission-holding" and #saves==0)')
        self.assertTrue(self.lua.globals().provider_tick(1)[0])
        self.lua.execute('assert(storage.mir5_se_worker_speed_provider_admitted.phase=="admission-saved" and #saves==1)')

        self.lua.globals().provider_candidate_normalize()
        self.stage("candidate")
        self.assertTrue(self.call("load")[0])
        event = self.event(True, {FIXTURE_NAME: {"old_version": "0.2.0", "new_version": "0.4.0"},
            "more-infinite-research": {"old_version": "5.0.20015", "new_version": "5.0.20018"}})
        self.assertTrue(self.call("configuration", event)[0])
        self.assertTrue(self.lua.globals().provider_tick(1)[0])
        self.lua.execute('assert(storage.mir5_se_worker_speed_provider_admitted.phase=="candidate-working" and game.lab~=nil)')

    def test_source_refuses_missing_or_wrong_direct_prerequisite_before_grants(self):
        for mutation, token in (
            ('game.forces.player.technologies["electricity"]=nil', "technology is absent: electricity"),
            ('local p=game.forces.player.technologies["worker-robots-speed-9"];p.prerequisites["se-energy-science-pack-4"]=nil;p.prerequisites["se-energy-science-pack-3"]=game.forces.player.technologies["se-energy-science-pack-3"]',
             "direct parents differ: worker-robots-speed-9"),
        ):
            with self.subTest(token=token):
                self.setUp()
                self.lua.execute(mutation)
                self.stage("source")
                ok, message = self.call("init")
                self.assertFalse(ok)
                self.assertIn(token, message)
                self.lua.execute('assert(storage.mir5_se_worker_speed_provider_admitted==nil and #markers==0 and #saves==0)')

    def test_source_refuses_reordered_fixed_prerequisite_before_writes(self):
        self.stage("source")
        self.lua.execute(r'''
          provider_fixed.rows[1],provider_fixed.rows[2]=provider_fixed.rows[2],provider_fixed.rows[1]
        ''')
        ok, message = self.call("init")
        self.assertFalse(ok)
        self.assertIn("declared order differs: automation-science-pack", message)
        self.lua.execute('assert(storage.mir5_se_worker_speed_provider_admitted==nil and #markers==0 and #saves==0)')

    def test_admission_refuses_mutated_completed_state_without_repair(self):
        self.source()
        self.stage("admission")
        event = self.event(False, {FIXTURE_NAME: {"old_version": "0.1.0", "new_version": "0.2.0"}})
        ok, message = self.call("configuration", event)
        self.assertTrue(ok, message)
        self.lua.execute('game.forces.player.technologies["worker-robots-speed-1"].researched=false')
        ok, message = self.lua.globals().provider_tick(1)
        self.assertFalse(ok)
        self.assertIn("completed prerequisite differs", message)
        self.lua.execute('assert(#saves==0 and game.forces.player.technologies["worker-robots-speed-1"].researched==false)')

    def test_old_opponent_is_passive_and_candidate_rejects_stale_provenance(self):
        self.admitted()
        self.stage("old")
        old_event = self.event(True, {FIXTURE_NAME: {"old_version": "0.2.0", "new_version": "0.3.0"}})
        ok, message = self.call("configuration", old_event)
        self.assertFalse(ok)
        self.assertIn("MIR_EXPECTED_SE_WORKER_SPEED_PROVIDER_OLD15_OPPONENT", message)
        self.lua.execute('assert(#saves==1 and storage.mir5_se_worker_speed_provider_admitted.phase=="admission-saved")')
        self.lua.globals().provider_candidate_normalize()
        self.lua.execute('storage.mir5_se_worker_speed_provider_admitted.provenance.source_mir="5.0.20014"')
        self.stage("candidate")
        event = self.event(True, {FIXTURE_NAME: {"old_version": "0.2.0", "new_version": "0.4.0"},
            "more-infinite-research": {"old_version": "5.0.20015", "new_version": "5.0.20018"}})
        ok, message = self.call("configuration", event)
        self.assertFalse(ok)
        self.assertIn("source provenance differs", message)

    def test_old_opponent_rejects_an_extra_mod_change_before_its_expected_token(self):
        self.admitted()
        self.stage("old")
        event = self.event(True, {FIXTURE_NAME: {"old_version": "0.2.0", "new_version": "0.3.0"},
            "undeclared-fixture": {"new_version": "1.0.0"}})
        ok, message = self.call("configuration", event)
        self.assertFalse(ok)
        self.assertIn("unexpected old mod change", message)
        self.assertNotIn("MIR_EXPECTED_SE_WORKER_SPEED_PROVIDER_OLD15_OPPONENT", message)
        self.lua.execute('assert(#saves==1 and #markers==3)')

    def test_candidate_requires_normalized_admitted_rows_and_real_non_scripted_level_ten_completion(self):
        self.candidate_started()
        self.lua.execute(r'''
          local state=storage.mir5_se_worker_speed_provider_admitted
          assert(state.phase=="candidate-working" and game.lab~=nil)
          assert(state.candidate.pre_work.player.worker.enabled==true and state.candidate.pre_work.player.worker.visible==false)
          assert(state.candidate.pre_work.foreign.worker.enabled==false and state.candidate.pre_work.foreign.worker.visible==true)
          assert(state.candidate.pre_work.earned.worker.enabled==false and state.candidate.pre_work.earned.worker.visible==true)
        ''')
        ok, message = self.lua.globals().provider_finish(False)
        self.assertTrue(ok, message)
        ok, message = self.lua.globals().provider_tick(2)
        self.assertTrue(ok, message)
        self.lua.execute(r'''
          local state=storage.mir5_se_worker_speed_provider_admitted
          assert(state.phase=="candidate-saved" and #state.candidate.ordinary_events==1)
          local event=state.candidate.ordinary_events[1]
          assert(event.name=="worker-robots-speed-10" and event.by_script==false and event.completed_level==10 and event.event_post_increment_level==11)
          assert(#saves==2 and saves[2]=="se-worker-speed-provider-candidate")
          local marker=markers[#markers]
          assert(marker.phase=="candidate-complete" and state.candidate.closed.player.worker.saved==0)
          assert(marker.candidate.lab.valid==true and marker.candidate.lab.name=="mir-fixture-se-worker-speed-provider-lab"
            and marker.candidate.lab.unit_number==91 and marker.candidate.lab.disabled_by_script==true)
          for _,name in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack","utility-science-pack",
            "space-science-pack","se-rocket-science-pack","se-energy-science-pack-4","se-deep-space-science-pack-1"})do
            assert(marker.candidate.lab.input[name]==64)
          end
          assert(marker.candidate.lab~=state.candidate.lab and marker.candidate.lab.get_inventory==nil)
        ''')

    def test_candidate_refills_bounded_lab_stacks_and_never_completes_with_exhausted_feed(self):
        self.candidate_started()
        ok, message = self.lua.globals().provider_finish(False)
        self.assertTrue(ok, message)
        self.lua.execute(r'''
          local feed=storage.mir5_se_worker_speed_provider_admitted.candidate.feed
          assert(#feed.topups==12)
          for _,name in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack","utility-science-pack",
            "space-science-pack","se-rocket-science-pack","se-energy-science-pack-4","se-deep-space-science-pack-1"})do
            assert(feed.accepted[name]==2400 and game.lab._input.get_item_count(name)==64)
          end
        ''')

        self.setUp()
        self.candidate_started()
        self.lua.globals().provider_disable_lab_refills()
        ok, message = self.lua.globals().provider_finish(False)
        self.assertFalse(ok)
        self.assertIn("world research input exhausted", message)
        self.lua.execute('assert(#saves==1 and storage.mir5_se_worker_speed_provider_admitted.phase=="candidate-working")')

    def test_candidate_refuses_scripted_completion_level_eleven_start_and_prework_mutation(self):
        self.candidate_started()
        ok, message = self.lua.globals().provider_finish(True)
        self.assertFalse(ok)
        self.assertIn("candidate ordinary completion differs", message)
        self.setUp()
        self.candidate_started()
        ok, message = self.lua.globals().provider_start_eleven()
        self.assertFalse(ok)
        self.assertIn("candidate level eleven research started", message)
        self.setUp()
        self.admitted()
        self.lua.globals().provider_candidate_normalize()
        self.stage("candidate")
        event = self.event(True, {FIXTURE_NAME: {"old_version": "0.2.0", "new_version": "0.4.0"},
            "more-infinite-research": {"old_version": "5.0.20015", "new_version": "5.0.20018"}})
        ok, message = self.call("configuration", event)
        self.assertTrue(ok, message)
        self.lua.execute('game.forces["mir5-se-worker-speed-provider-foreign"].research_queue={}')
        ok, message = self.lua.globals().provider_tick(1)
        self.assertFalse(ok)
        self.assertIn("candidate foreign cap frame differs", message)
        self.lua.execute('assert(game.lab==nil)')

    def test_candidate_refuses_wrong_player_flags_bonus_and_completed_row_before_save(self):
        self.admitted()
        self.lua.globals().provider_candidate_normalize()
        self.lua.execute('game.forces.player.technologies["worker-robots-speed-10"].enabled=false;game.forces.player.technologies["worker-robots-speed-10"].visible_when_disabled=true')
        self.stage("candidate")
        event = self.event(True, {FIXTURE_NAME: {"old_version": "0.2.0", "new_version": "0.4.0"},
            "more-infinite-research": {"old_version": "5.0.20015", "new_version": "5.0.20018"}})
        ok, message = self.call("configuration", event)
        self.assertFalse(ok)
        self.assertIn("candidate player cap frame differs", message)
        self.lua.execute('assert(game.lab==nil and #saves==1)')

        self.setUp()
        self.candidate_started()
        self.assertTrue(self.lua.globals().provider_finish(False)[0])
        self.lua.execute('game.forces.player.worker_robots_speed_modifier=999')
        ok, message = self.lua.globals().provider_tick(1)
        self.assertFalse(ok)
        self.assertIn("level eleven started or queued", message)
        self.lua.execute('assert(#saves==1)')

        self.setUp()
        self.candidate_started()
        self.assertTrue(self.lua.globals().provider_finish(False)[0])
        self.lua.execute('game.forces.player.technologies["electricity"].enabled=false')
        ok, message = self.lua.globals().provider_tick(1)
        self.assertFalse(ok)
        self.assertIn("candidate changed completed prerequisite rows", message)
        self.lua.execute('assert(#saves==1)')

    def test_exact_zero_saved_progress_is_not_a_near_zero_default(self):
        self.admitted()
        self.lua.execute('game.forces.player.technologies["worker-robots-speed-1"].saved_progress=1e-9')
        self.lua.globals().provider_candidate_normalize()
        self.stage("candidate")
        event = self.event(True, {FIXTURE_NAME: {"old_version": "0.2.0", "new_version": "0.4.0"},
            "more-infinite-research": {"old_version": "5.0.20015", "new_version": "5.0.20018"}})
        ok, message = self.call("configuration", event)
        self.assertFalse(ok)
        self.assertIn("completed prerequisite differs", message)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    arguments = parser.parse_args()
    sys.path.insert(0, str(arguments.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(SEWorkerSpeedProviderSourceTests))
    sys.exit(0 if result.wasSuccessful() else 1)

"""Controlled Imersite handoff opponents; native save qualification is separate."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ImersiteMigrationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          migration = require("runtime.k2_imersite_migration")
          contract = require("research.k2_imersite")
          E,T,H,C = contract.early.id,contract.continuation.id,contract.carriers[1].id,contract.carriers[2].id
          function state(level, researched, progress)
            return {level=level,researched=researched == true,saved_progress=progress or 0}
          end
          function world(completed)
            local rows, technologies, values = {}, {}, {}
            local recipe = {productivity_bonus=0.123}
            local function total()
              local sum = 0
              for id,row in pairs(rows) do
                local first = (id == T or id == C) and 4 or 1
                sum = sum + row.level-first+(row.researched and 1 or 0)
              end
              recipe.productivity_bonus = 0.123+sum*0.02
            end
            for _,id in ipairs({E,T,H,C}) do
              local first = (id == T or id == C) and 4 or 1
              rows[id] = {name=id,level=first,researched=false,saved_progress=0,enabled=true,visible_when_disabled=false,
                research_unit_energy=1800,
                prototype={max_level=id == E and 3 or 4294967295,hidden=id == H or id == C,
                  effects={{type="change-recipe-productivity",recipe="kr-imersite-powder",change=0.02}},
                  prerequisites=id == T and {{name=E}} or {}}}
              technologies[id] = setmetatable({}, {
                __index=function(_,key) return rows[id][key] end,
                __newindex=function(_,key,value)
                  rows[id][key]=value
                  -- LuaTechnology.level enables the technology.  The migration
                  -- must therefore restore any unqueued foreign disablement.
                  if key == "level" then rows[id].enabled=true end
                  if key == "enabled" and value == false and values.drop_public_queue == id then
                    values.research_queue,values.current_research,values.research_progress={},nil,0
                  end
                  total()
                end})
            end
            rows[H].level = completed+1; rows[H].saved_progress=0.42
            values.index,values.technologies,values.recipes=1,technologies,{["kr-imersite-powder"]=recipe}
            values.research_queue,values.current_research,values.research_progress={technologies[H]},technologies[H],0.42
            local force = setmetatable({}, {
              __index=function(_,key) return values[key] end,
              __newindex=function(_,key,value)
                if key == "research_queue" then
                  if values.reject_once then values.reject_once=false; error("opposing native queue refusal") end
                  values.research_queue=value; values.current_research=value[1]
                  if values.corrupt_queue_current_once then
                    values.current_research=technologies[values.corrupt_queue_current_once]
                    values.corrupt_queue_current_once=nil
                  end
                  if value[1] == nil then values.research_progress=0 end
                elseif key == "research_progress" then
                  if values.current_research == nil then error("No research in progress") end
                  values.progress_writes=(values.progress_writes or 0)+1
                  values.progress_write_currents=values.progress_write_currents or {}
                  values.progress_write_currents[#values.progress_write_currents+1]=values.current_research.name
                  values.research_progress=value
                else values[key]=value end
              end})
            total()
            return force,rows,values
          end
        ''')

    def test_all_released_boundary_levels_map_without_awarding_credit(self):
        self.lua.execute('''
          for _,completed in ipairs({0,2,3,7}) do
            local plan = migration.plan(state(completed+1,false,0.42),state(4),state(1),{H},H,0.42)
            assert(plan.earned == completed and plan.progress == 0.42)
            assert(plan.early.level == math.min(3,completed+1) and plan.early.researched == (completed >= 3))
            assert(plan.tail.level == math.max(4,completed+1) and not plan.tail.researched)
            assert(plan.current == (completed < 3 and E or T))
            assert(plan.queue[1] == plan.current)
          end
          local plan = migration.plan(state(3,false,.42),state(4),state(1),{H,H,H,"foreign"},H,.42)
          assert(plan.queue[1] == E and plan.queue[2] == T and plan.queue[3] == T and plan.queue[4] == "foreign")
        ''')

    def test_handoff_keeps_bonus_offset_progress_and_consumes_only_holders(self):
        self.lua.execute('''
          for _,completed in ipairs({0,2,3,7}) do
            local force,rows = world(completed)
            local bonus, records = force.recipes["kr-imersite-powder"].productivity_bonus,{}
            assert(migration.reconcile_force(force,.02,records))
            assert(math.abs(force.recipes["kr-imersite-powder"].productivity_bonus-bonus) < 1e-9)
            assert(force.research_progress == .42 and records[1].earned == completed)
            assert(rows[H].level == 1 and not rows[H].researched and not rows[H].enabled)
            assert(rows[C].level == 4 and not rows[C].researched and not rows[C].enabled)
            assert(not migration.reconcile_force(force,.02,records))
            assert(math.abs(force.recipes["kr-imersite-powder"].productivity_bonus-bonus) < 1e-9)
          end
        ''')

    def test_queue_refusal_rolls_back_named_states_and_retains_carrier_credit(self):
        self.lua.execute('''
          local force,rows,values = world(7)
          local bonus,records = force.recipes["kr-imersite-powder"].productivity_bonus,{}
          values.reject_once = true
          local ok,message = pcall(migration.reconcile_force,force,.02,records)
          assert(not ok and tostring(message):find("opposing native queue refusal",1,true))
          assert(rows[H].level == 8 and rows[H].enabled and rows[E].level == 1 and rows[T].level == 4)
          assert(force.current_research.name == H and force.research_progress == .42 and next(records) == nil)
          assert(math.abs(force.recipes["kr-imersite-powder"].productivity_bonus-bonus) < 1e-9)
        ''')

    def test_detached_work_handoff_never_sets_force_progress_without_current_research(self):
        self.lua.execute('''
          for _,completed in ipairs({0,2,3,5,7}) do
            local force,rows,values = world(completed)
            force.research_queue = {}
            local bonus,records = force.recipes["kr-imersite-powder"].productivity_bonus,{}
            assert(migration.reconcile_force(force,.02,records))
            assert(force.current_research == nil and #force.research_queue == 0)
            assert(force.research_progress == 0 and values.progress_writes == nil)
            local destination = completed < 3 and E or T
            assert(rows[destination].saved_progress == .42)
            assert(rows[destination].level == (completed < 3 and completed+1 or math.max(4,completed+1)))
            assert(rows[H].level == 1 and rows[H].saved_progress == 0 and not rows[H].enabled)
            assert(rows[C].level == 4 and rows[C].saved_progress == 0 and not rows[C].enabled)
            assert(records[1].earned == completed)
            assert(math.abs(force.recipes["kr-imersite-powder"].productivity_bonus-bonus) < 1e-9)
            assert(not migration.reconcile_force(force,.02,records))
            assert(values.progress_writes == nil)
          end
        ''')

    def test_handoff_preserves_unqueued_public_disablement_and_visibility(self):
        self.lua.execute('''
          local force,rows = world(5)
          force.research_queue = {}
          rows[E].enabled=false; rows[E].visible_when_disabled=true
          rows[T].enabled=false; rows[T].visible_when_disabled=false
          local records={}
          assert(migration.reconcile_force(force,.02,records))
          assert(not rows[E].enabled and rows[E].visible_when_disabled)
          assert(not rows[T].enabled and not rows[T].visible_when_disabled)
          assert(force.current_research == nil and #force.research_queue == 0 and force.research_progress == 0)
          assert(rows[H].level == 1 and not rows[H].enabled and rows[C].level == 4 and not rows[C].enabled)
          assert(records[1].earned == 5)
        ''')

    def test_unmapped_public_queue_preserves_foreign_disablement(self):
        self.lua.execute('''
          local force,rows = world(5)
          rows[T].enabled=false; rows[T].visible_when_disabled=true
          force.research_queue={force.technologies[T]}
          assert(migration.reconcile_force(force,.02,{}))
          -- T was already the public queue entry. Its level write must not use
          -- that unrelated queue position to replace foreign disablement.
          assert(not rows[T].enabled and rows[T].visible_when_disabled)
          assert(force.current_research.name == T and force.research_progress == .42)
        ''')

    def test_mapped_public_queue_keeps_activation_for_direct_and_verified_legacy_carriers(self):
        self.lua.execute('''
          local force,rows = world(5)
          rows[T].enabled=false; rows[T].visible_when_disabled=true
          assert(migration.reconcile_force(force,.02,{}))
          assert(rows[T].enabled and rows[T].visible_when_disabled)

          force,rows = world(5)
          rows[T].enabled=false; rows[T].visible_when_disabled=true
          local legacy={schema=3,force_index=1,source="json-two-holders-v1",source_version="4.6.21000",
            phase="holder-retained-retryable",early=state(6,false,.42),continuation=state(4),
            queue_before={H},queue_after_removal={H},current_before=H,current_after_removal=H,progress_before=.42}
          assert(migration.reconcile_force(force,.02,{},legacy))
          assert(rows[T].enabled and rows[T].visible_when_disabled)
        ''')

    def test_public_flag_queue_mutation_rolls_back_before_recording_handoff(self):
        self.lua.execute('''
          local force,rows,values = world(5)
          rows[T].enabled=false; rows[T].visible_when_disabled=true
          force.research_queue={force.technologies[T]}
          values.drop_public_queue=T
          local bonus,records=force.recipes["kr-imersite-powder"].productivity_bonus,{}
          local ok,message=pcall(migration.reconcile_force,force,.02,records)
          assert(not ok and tostring(message):find("queue readback differs",1,true))
          assert(next(records) == nil and rows[H].level == 6 and rows[H].saved_progress == .42 and rows[H].enabled)
          assert(rows[T].level == 4 and not rows[T].enabled and rows[T].visible_when_disabled)
          assert(force.current_research.name == T and #force.research_queue == 1 and force.research_progress == .42)
          assert(math.abs(force.recipes["kr-imersite-powder"].productivity_bonus-bonus) < 1e-9)
        ''')

    def test_unexpected_queue_current_refuses_before_progress_write(self):
        self.lua.execute('''
          local force,rows,values = world(5)
          values.corrupt_queue_current_once=E
          local bonus,records=force.recipes["kr-imersite-powder"].productivity_bonus,{}
          local ok,message=pcall(migration.reconcile_force,force,.02,records)
          assert(not ok and tostring(message):find("queue readback differs",1,true))
          assert(#values.progress_write_currents == 1 and values.progress_write_currents[1] == H)
          assert(next(records) == nil and rows[H].level == 6 and rows[H].saved_progress == .42 and rows[H].enabled)
          assert(force.current_research.name == H and #force.research_queue == 1 and force.research_progress == .42)
          assert(math.abs(force.recipes["kr-imersite-powder"].productivity_bonus-bonus) < 1e-9)
        ''')

    def test_detached_queue_refusal_preserves_original_error_and_carrier_work(self):
        self.lua.execute('''
          local force,rows,values = world(5)
          force.research_queue = {}
          local bonus,records = force.recipes["kr-imersite-powder"].productivity_bonus,{}
          values.reject_once = true
          local ok,message = pcall(migration.reconcile_force,force,.02,records)
          assert(not ok and tostring(message):find("opposing native queue refusal",1,true))
          assert(force.current_research == nil and #force.research_queue == 0 and force.research_progress == 0)
          assert(values.progress_writes == nil and next(records) == nil)
          assert(rows[H].level == 6 and rows[H].saved_progress == .42 and rows[H].enabled)
          assert(rows[E].level == 1 and rows[T].level == 4)
          assert(math.abs(force.recipes["kr-imersite-powder"].productivity_bonus-bonus) < 1e-9)
        ''')

    def test_malformed_or_conflicting_sources_fail_before_consumption(self):
        self.lua.execute('''
          local ok = pcall(migration.plan,state(3),state(7),state(1),{C},C,.42)
          assert(not ok)
          ok = pcall(migration.plan,state(8),state(7),state(1),{H},H,.42)
          assert(not ok)
          ok = pcall(migration.plan,state(0),state(4),state(1),{},nil,0)
          assert(not ok)
          local force,rows = world(7)
          rows[E].level = 2
          local records = {}
          ok = pcall(migration.reconcile_force,force,.02,records)
          assert(not ok and rows[H].level == 8 and rows[E].level == 2 and next(records) == nil)
        ''')

    def test_foreign_effect_and_reactivated_carrier_cannot_gain_ownership(self):
        self.lua.execute('''
          local force,rows = world(7)
          rows[H].prototype.effects[1].recipe = "kr-imersite-crystal"
          assert(not pcall(migration.reconcile_force,force,.02,{}))
          assert(rows[H].level == 8 and rows[E].level == 1)
          force,rows = world(7)
          assert(not pcall(migration.reconcile_force,force,.02,{[1]={status="completed"}}))
          assert(rows[H].level == 8 and rows[E].level == 1)
        ''')

    def test_public_fractional_work_and_unverified_old_rollback_are_never_overwritten(self):
        self.lua.execute('''
          local force,rows = world(7)
          rows[T].level=8; rows[T].saved_progress=.25
          assert(not pcall(migration.reconcile_force,force,.02,{}))
          assert(rows[T].saved_progress == .25 and rows[H].level == 8)
          force,rows = world(7)
          local legacy = {schema=3,force_index=1,source="json-two-holders-v1",source_version="4.6.21000",
            phase="holder-retained-rollback-failed",early=state(8,false,.42),continuation=state(4),
            queue_before={H},queue_after_removal={H},current_before=H,current_after_removal=H,progress_before=.42}
          assert(not pcall(migration.reconcile_force,force,.02,{},legacy))
          assert(rows[H].level == 8 and rows[E].level == 1 and force.research_progress == .42)
          legacy.phase="unexpected"
          assert(not pcall(migration.reconcile_force,force,.02,{},legacy))
          legacy.phase="holder-retained-retryable"
          assert(migration.reconcile_force(force,.02,{},legacy))
          assert(rows[T].level == 8 and rows[H].level == 1 and force.research_progress == .42)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ImersiteMigrationTests))
    sys.exit(0 if result.wasSuccessful() else 1)

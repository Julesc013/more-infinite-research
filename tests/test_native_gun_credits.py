"""Independent two-category paid-count/lifecycle controls, not native acceptance."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeGunCreditTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute(r'''
          package.path=player_root.."/?.lua;"..player_root.."/?/init.lua"
          package.cpath=""
          main_id="recipe-prod-research_electric_shooting_speed-1"
          names={electric={
            positive="mir-native-credit-research_electric_shooting_speed-electric-positive",
            negative="zz-mir-native-credit-research_electric_shooting_speed-electric-negative"},
            tesla={positive="mir-native-credit-research_electric_shooting_speed-tesla-positive",
            negative="zz-mir-native-credit-research_electric_shooting_speed-tesla-negative"}}
          storage={}; game={forces={}}
          script={active_mods={base="2.1.23",["space-age"]="2.0.0",["more-infinite-research"]="5.0.21004"}}
          prototypes={get_history=function(kind,name) assert(kind=="technology");return {created="more-infinite-research"} end}
          function copy(value)
            if type(value)~="table" then return value end
            local out={};for k,v in pairs(value) do out[k]=copy(v) end;return out
          end
          function same(a,b)
            if type(a)~=type(b) then return false end
            if type(a)~="table" then return a==b end
            for k,v in pairs(a) do if not same(v,b[k]) then return false end end
            for k in pairs(b) do if a[k]==nil then return false end end
            return true
          end
          function rejected(body)
            local ok,message=pcall(body);assert(not ok,"missing refusal")
            assert(tostring(message):find("MIR native gun credit",1,true),message)
          end
          function technology(name,n,effects,hidden)
            return {name=name,valid=true,level=n+1,researched=false,enabled=not hidden,
              visible_when_disabled=not hidden,saved_progress=.27,
              research_unit_count=hidden and 1 or 135,research_unit_energy=hidden and 60 or 3600,
              research_unit_ingredients={{name="automation-science-pack",amount=hidden and 1 or 2}},
              prototype={name=name,level=1,max_level=4294967295,hidden=hidden,upgrade=true,
                enabled=not hidden,visible_when_disabled=not hidden,effects=effects}}
          end
          function set_mask(force,electric,tesla,scalar)
            scalar=scalar or force.scalar
            force.scalar=scalar
            local main=force.technologies[main_id];local effects={}
            for _,category in ipairs({"electric","tesla"}) do
              local included=category=="electric" and electric or category=="tesla" and tesla
              if included then effects[#effects+1]={type="gun-speed",ammo_category=category,modifier=scalar} end
              if force.technologies[names[category].positive] then
                force.technologies[names[category].positive].prototype.effects[1].modifier=scalar
                force.technologies[names[category].negative].prototype.effects[1].modifier=included and -scalar or 0
              end
            end
            main.prototype.effects=effects
            main.prototype.enabled=electric or tesla
          end
          function make_force(index,n,electric,tesla,scalar)
            scalar=scalar or .17
            local technologies={}
            local force={valid=true,index=index,technologies=technologies,scalar=scalar,
              research_queue={},research_progress=.42,foreign={electric=.63,tesla=.91}}
            technologies[main_id]=technology(main_id,n,{},false)
            technologies[main_id].force=force
            for _,category in ipairs({"electric","tesla"}) do
              for _,direction in ipairs({"positive","negative"}) do
                local id=names[category][direction]
                technologies[id]=technology(id,0,{{type="gun-speed",ammo_category=category,modifier=0}},true)
                technologies[id].force=force
              end
            end
            set_mask(force,electric,tesla,scalar)
            technologies.foreign=technology("foreign",8,{{type="gun-speed",ammo_category="electric",modifier=.23}},false)
            technologies.foreign.saved_progress=.19
            setmetatable(technologies,{__pairs=function() error("world technology scan") end})
            game.forces[index]=force;return force
          end
          function paid(force,category)
            local result=0
            for _,effect in ipairs(force.technologies[main_id].prototype.effects) do
              if effect.ammo_category==category then result=result+(force.technologies[main_id].level-1)*effect.modifier end
            end
            for _,direction in ipairs({"positive","negative"}) do
              local holder=force.technologies[names[category][direction]]
              result=result+(holder.level-1)*holder.prototype.effects[1].modifier
            end
            return result
          end
          function expect(force,electric,tesla)
            assert(math.abs(paid(force,"electric")-electric)<1e-12,"electric paid amount")
            assert(math.abs(paid(force,"tesla")-tesla)<1e-12,"tesla paid amount")
          end
          function public_snapshot(force)
            local main=force.technologies[main_id]
            return {level=main.level,researched=main.researched,enabled=main.enabled,saved_progress=main.saved_progress,
              progress=force.research_progress,queue=force.research_queue,current=force.current_research,
              foreign=copy(force.technologies.foreign),offsets=copy(force.foreign)}
          end
          function assert_public(force,before)
            local after=public_snapshot(force)
            assert(before.level==after.level and before.researched==after.researched and before.enabled==after.enabled
              and before.saved_progress==after.saved_progress and before.progress==after.progress)
            assert(before.queue==after.queue and before.current==after.current)
            assert(same(before.foreign,after.foreign) and same(before.offsets,after.offsets))
          end
          function known_event(old)
            return {mod_startup_settings_changed=false,mod_changes={
              ["more-infinite-research"]={old_version=old or "5.0.21003",new_version="5.0.21004"}}}
          end
          function configure(event)
            local plans=credit.preflight(event);credit.on_configuration_changed(event,plans)
          end
          function reload()
            package.loaded["runtime.native_gun_credits"]=nil
            credit=require("runtime.native_gun_credits")
          end
          reload()
        ''')

    def test_published_partial_paid_mask_and_all_public_work_are_preserved(self):
        self.lua.execute('''
          local f=make_force(1,4,false,true);local main=f.technologies[main_id]
          f.current_research=main;f.research_queue={main,f.technologies.foreign}
          local before=public_snapshot(f)
          configure(known_event())
          expect(f,.68,.68);assert_public(f,before)
          assert(main.enabled and #main.prototype.effects==1)
          assert(not credit.needs_research_events())
          main.level=6 -- one normal uncovered Tesla completion; no MIR callback
          expect(f,.68,.85)
          for _,category in ipairs({"electric","tesla"}) do
            for _,id in pairs(names[category]) do assert(not f.technologies[id].enabled) end
          end
        ''')

    def test_repeated_provider_removal_readmission_retuning_and_zero_scalar(self):
        self.lua.execute('''
          local f=make_force(1,4,false,true)
          configure(known_event());f.technologies[main_id].level=7
          expect(f,.68,1.02)
          set_mask(f,true,true);configure({});expect(f,.68,1.02)
          assert(f.technologies[names.electric.negative].level==3)
          f.technologies[main_id].level=8;expect(f,.85,1.19)
          set_mask(f,false,true);configure({});expect(f,.85,1.19)
          assert(f.technologies[names.electric.negative].level==1)
          set_mask(f,true,true);configure({});expect(f,.85,1.19)
          set_mask(f,true,true,.31);configure({});expect(f,1.55,2.17)
          set_mask(f,false,true,0);configure({});expect(f,0,0)
          assert(f.technologies[names.electric.positive].level==6)
        ''')

    def test_fully_retired_pending_work_keeps_the_prior_mask_then_unsubscribes(self):
        self.lua.execute('''
          local f=make_force(1,3,false,true);configure(known_event())
          local main=f.technologies[main_id];main.level=6
          f.current_research=main;f.research_queue={main,main,f.technologies.foreign}
          set_mask(f,false,false)
          main.enabled=false -- the existing lifecycle owns public disablement
          local before=public_snapshot(f);configure({});assert_public(f,before)
          expect(f,.51,.85);assert(not main.enabled and credit.needs_research_events())
          main.level=7
          assert(not credit.on_research_finished({research=main}));expect(f,.51,1.02)
          main.level=8
          assert(credit.on_research_finished({research=main}));expect(f,.51,1.19)
          assert(not credit.needs_research_events())
          assert(not credit.on_research_finished({research=f.technologies[names.tesla.positive]}))
        ''')

    def test_cancelled_private_work_does_not_receive_new_payable_rights(self):
        self.lua.execute('''
          local f=make_force(1,2,true,true);credit.on_init()
          local main=f.technologies[main_id];f.current_research=main;f.research_queue={main,main}
          set_mask(f,false,false);configure({});expect(f,.34,.34)
          assert(not credit.on_research_cancelled({force=f,research={[main_id]=1}}))
          assert(credit.on_research_cancelled({force=f,research={[main_id]=1}}))
          assert(not credit.needs_research_events())
          configure({});assert(not credit.needs_research_events())
          expect(f,.34,.34)
        ''')

    def test_first_unknown_paid_or_detached_mask_refuses_before_any_force_write(self):
        self.lua.execute('''
          for _,kind in ipairs({"paid","detached","queued"}) do
            storage={};game.forces={}
            local a=make_force(1,3,false,true)
            local b=make_force(2,kind=="paid" and 2 or 0,false,true)
            b.technologies[main_id].saved_progress=kind=="detached" and .27 or 0
            if kind=="queued" then b.research_queue={b.technologies[main_id]} end
            local before_a=public_snapshot(a)
            rejected(function() configure({}) end)
            assert(storage.mir_native_gun_credits==nil)
            assert(a.technologies[names.electric.positive].level==1)
            assert_public(a,before_a)
          end
        ''')

    def test_known_beta_input_opponents_and_native_shape_drift_refuse(self):
        self.lua.execute('''
          for _,kind in ipairs({"setting","provider","version","destination","foreign","scalar","missing"}) do
            storage={};game.forces={};local f=make_force(1,2,false,true)
            local event=known_event()
            if kind=="setting" then event.mod_startup_settings_changed=true end
            if kind=="provider" then event.mod_changes.provider={old_version="1",new_version="2"} end
            if kind=="version" then event.mod_changes["more-infinite-research"].old_version="5.0.21005" end
            if kind=="destination" then event.mod_changes["more-infinite-research"].new_version="5.0.21099" end
            if kind=="foreign" then prototypes.get_history=function() return {created="foreign"} end end
            if kind=="scalar" then f.technologies[names.tesla.negative].prototype.effects[1].modifier=-.2 end
            if kind=="missing" then f.technologies[names.electric.positive]=nil end
            rejected(function() configure(event) end);assert(storage.mir_native_gun_credits==nil)
            prototypes.get_history=function() return {created="more-infinite-research"} end
          end
        ''')

    def test_all_force_preflight_and_stale_plan_do_not_partially_apply(self):
        self.lua.execute('''
          local a=make_force(1,3,false,true);local b=make_force(2,4,false,true)
          b.technologies[names.tesla.positive].level=2
          rejected(function() configure(known_event()) end)
          assert(storage.mir_native_gun_credits==nil and a.technologies[names.electric.positive].level==1)
          b.technologies[names.tesla.positive].level=1
          local plans=credit.preflight(known_event())
          b.technologies[main_id].level=6
          rejected(function() credit.apply(plans) end)
          assert(storage.mir_native_gun_credits==nil and a.technologies[names.electric.positive].level==1)
        ''')

    def test_reset_only_restores_private_flags_and_does_not_repair_levels(self):
        self.lua.execute('''
          local f=make_force(1,4,false,true);configure(known_event())
          local ledger=copy(storage);local before=public_snapshot(f)
          for _,category in ipairs({"electric","tesla"}) do
            for _,id in pairs(names[category]) do f.technologies[id].enabled=true;f.technologies[id].visible_when_disabled=true end
          end
          credit.on_technology_effects_reset({force=f});assert_public(f,before)
          assert(same(storage,ledger));expect(f,.68,.68)
          assert(f.technologies[names.electric.positive].level==5)
        ''')

    def test_on_load_is_read_only_and_reconstructs_only_pending_subscription(self):
        self.lua.execute('''
          local f=make_force(1,2,true,true);credit.on_init()
          f.research_queue={f.technologies[main_id]};set_mask(f,false,false);configure({})
          local saved=copy(storage);reload()
          game=setmetatable({},{__index=function() error("game access on load") end})
          prototypes=setmetatable({},{__index=function() error("prototype access on load") end})
          credit.on_load();assert(credit.needs_research_events() and same(saved,storage))
        ''')

    def test_force_merge_retains_destination_history_and_clears_source_index(self):
        self.lua.execute('''
          local source=make_force(1,4,false,true);configure(known_event())
          local dest=make_force(2,2,true,true);configure({})
          set_mask(dest,false,true);configure({});expect(dest,.34,.34)
          local before=public_snapshot(dest)
          credit.on_forces_merged({source_index=1,destination=dest})
          expect(dest,.34,.34);assert_public(dest,before)
          assert(storage.mir_native_gun_credits.forces[1]==nil)
          local reused=make_force(1,0,false,true);reused.technologies[main_id].saved_progress=0
          credit.on_force_created({force=reused});expect(reused,0,0)
          assert(storage.mir_native_gun_credits.forces[1].positive.electric==0)
        ''')

    def test_unearned_and_unchanged_full_public_baselines_need_no_guessed_old_mask(self):
        self.lua.execute('''
          local f=make_force(1,0,false,true);f.technologies[main_id].saved_progress=0
          configure({});expect(f,0,0)
          local old=make_force(2,7,true,true);local before=public_snapshot(old)
          configure({});expect(old,1.19,1.19);assert_public(old,before)
          assert(not credit.needs_research_events())
          credit.on_force_reset({force=f});expect(f,0,0)
        ''')

    def test_inactive_corrupt_force_record_refuses_before_any_holder_write(self):
        self.lua.execute('''
          local f=make_force(1,3,false,true)
          storage.mir_native_gun_credits={schema=1,forces={[99]={}}}
          local saved=copy(storage)
          rejected(function() configure(known_event()) end)
          assert(f.technologies[names.electric.positive].level==1,
            "corrupt inactive force was discovered after native holder write")
          assert(same(saved,storage),"corrupt saved state was partially changed")
        ''')

    def test_corrupt_ledger_and_holder_ranges_refuse_without_state_repair(self):
        self.lua.execute('''
          local f=make_force(1,3,false,true);configure(known_event())
          f.technologies[names.electric.positive].level=6
          local saved=copy(storage)
          rejected(function() configure({}) end);assert(same(saved,storage))
          storage.mir_native_gun_credits.schema=2;saved=copy(storage)
          rejected(function() configure({}) end);assert(same(saved,storage))
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", required=True)
    args, remaining = parser.parse_known_args()
    sys.path.insert(0, args.lua_runtime_dir)
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0], *remaining])

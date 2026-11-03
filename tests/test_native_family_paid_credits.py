"""Independent contribution-mask/unfinished-work controls for five MIR families.

Fake native technologies expose signed completed-level effects. No engine,
save, renderer or scientific-work qualification follows from these controls.
"""
import argparse
import json
from pathlib import Path
import sys
import unittest

import test_native_credits as fixture


class NativeFamilyPaidCreditsTests(unittest.TestCase):
    def setUp(self):
        fixture.LuaRuntime = LuaRuntime
        case = fixture.NativeCreditRuntimeTests()
        case.setUp()
        self.lua = case.lua
        self.lua.execute(r'''
          GROUPS={research_steel={
            {recipe="alternate-steel",change=.17},{recipe="multi-native",change=.17},
            {recipe="steel-plate",change=.17},{recipe="casting-steel",change=.17}},
            research_low_density_structure={{recipe="multi-native",change=.1}}}
          local function copy(value)
            if type(value)~="table" then return value end
            local out={};for k,v in pairs(value) do out[k]=copy(v) end;return out
          end
          function reload_credits(active,target_id)
            script={active_mods=active or {base="2.1.23",["space-age"]="2.1.23",["more-infinite-research"]="5.0.21003"}}
            require("platform.target").id=target_id or "f210"
            prototypes={technology={},mod_data={
              ["more-infinite-research-native-adoptions"]={data={schema=1,owners={},withheld={},credits=copy(GROUPS)}}},
              get_history=function(_,name) return {created=foreign_creation==name and "foreign" or "more-infinite-research"} end}
            package.loaded["research.catalogue"]=nil
            package.loaded["runtime.catalogue"]=nil
            package.loaded["runtime.native_credits"]=nil
            native_credits=require("runtime.native_credits")
          end
          function make_collected_force(index,level,mask,private)
            local force={index=index,valid=true,technologies=setmetatable({}, {
              __pairs=function()error("whole technology traversal")end}),_states={},
              foreign_bonus=17.25,recipes=setmetatable({}, {__index=function()error("aggregate recipe read")end}),
              reset_technology_effects=function()error("force reset")end,research_progress=.42}
            for _,d in ipairs(native_credit_definitions.collected_descriptors(GROUPS)) do
              if not force.technologies[d.main_id] then
                local t,s=make_technology(d.main_id,{name=d.main_id,level=1,max_level=UINT32_MAX,
                  hidden=private==true,effects={}},level or 1,false,true)
                t.force=force;force.technologies[d.main_id]=t;force._states[d.main_id]=s
              end
              for _,direction in ipairs({"positive","negative"}) do
                local name=direction=="positive" and d.positive_id or d.negative_id
                local t,s=make_technology(name,{name=name,level=1,max_level=UINT32_MAX,hidden=true,
                  enabled=false,visible_when_disabled=false,effects={{type="change-recipe-productivity",
                    recipe=d.recipe,change=direction=="positive" and d.change or -d.change}}},1,false,false)
                t.force=force;force.technologies[name]=t;force._states[name]=s
              end
            end
            local t,s=make_technology("foreign",{name="foreign",level=1,max_level=UINT32_MAX,effects={}},3,false,false)
            t.force=force;force.technologies.foreign=t;force._states.foreign=s
            game.forces[index]=force;set_mask(force,mask or {},private)
            return force
          end
          function set_mask(force,mask,private)
            local seen={}
            for _,d in ipairs(native_credit_definitions.collected_descriptors(GROUPS)) do
              local proto=force.technologies[d.main_id].prototype
              if not seen[d.main_id] then proto.effects={};proto.hidden=private==true;seen[d.main_id]=true end
              if mask[d.family.."\0"..d.recipe] then
                proto.effects[#proto.effects+1]={type="change-recipe-productivity",recipe=d.recipe,change=d.change}
              end
            end
          end
          function key(family,recipe)return family.."\0"..recipe end
          function record(force,family,recipe)
            return storage.mir_native_credits and storage.mir_native_credits.forces[force.index]
              and storage.mir_native_credits.forces[force.index][key(family,recipe)]
          end
          function own_contribution(force,family,recipe)
            local wanted
            for _,d in ipairs(native_credit_definitions.collected_descriptors(GROUPS)) do
              if d.family==family and d.recipe==recipe then wanted=d end
            end
            local function completed(t)return t.level-1+(t.researched and 1 or 0)end
            local main=force.technologies[wanted.main_id];local included=false
            for _,e in ipairs(main.prototype.effects) do if e.recipe==recipe then included=true end end
            return wanted.change*((included and completed(main) or 0)
              +completed(force.technologies[wanted.positive_id])-completed(force.technologies[wanted.negative_id]))
          end
          function close(a,b)assert(math.abs(a-b)<1e-8,tostring(a).." differs "..tostring(b))end
          function no_foreign_write(force)
            assert(force.foreign_bonus==17.25 and not force.technologies.foreign.enabled)
            assert(force._states.foreign.writes.enabled==0 and force._states.foreign.writes.level==0)
          end
          function advance(force,id,level,researched)
            force._states[id].level=level;force._states[id].researched=researched
          end
          reload_credits()
        ''')

    def test_two_histories_keep_distinct_paid_masks_at_identical_destination(self):
        self.lua.execute(r'''
          local steel="research_steel";local simple=key(steel,"alternate-steel");local multi=key(steel,"multi-native")
          local a=make_collected_force(1,8,{[simple]=true})
          local b=make_collected_force(2,1,{[simple]=true})
          native_credits.on_init()
          set_mask(a,{[simple]=true,[multi]=true});set_mask(b,{[simple]=true,[multi]=true})
          native_credits.on_configuration_changed()
          advance(b,"recipe-prod-research_steel-1",8,false)
          close(own_contribution(a,steel,"multi-native"),0)
          close(own_contribution(b,steel,"multi-native"),7*.17)
          set_mask(a,{},true);set_mask(b,{},true)
          native_credits.on_configuration_changed()
          close(own_contribution(a,steel,"alternate-steel"),7*.17)
          close(own_contribution(b,steel,"alternate-steel"),7*.17)
          close(own_contribution(a,steel,"multi-native"),0)
          close(own_contribution(b,steel,"multi-native"),7*.17)
          assert(record(a,steel,"multi-native").offset==0 and record(b,steel,"multi-native").offset==7)
          no_foreign_write(a);no_foreign_write(b)
        ''')

    def test_same_recipe_in_two_families_has_distinct_native_credit_rights(self):
        self.lua.execute(r'''
          local steel,lds="research_steel","research_low_density_structure"
          local force=make_collected_force(1,5,{[key(steel,"multi-native")]=true})
          native_credits.on_init()
          set_mask(force,{[key(lds,"multi-native")]=true})
          native_credits.on_configuration_changed()
          assert(record(force,steel,"multi-native")~=record(force,lds,"multi-native"))
          assert(record(force,steel,"multi-native").offset==4)
          assert(record(force,lds,"multi-native").offset==-4)
          close(own_contribution(force,steel,"multi-native"),4*.17)
          close(own_contribution(force,lds,"multi-native"),0)
          no_foreign_write(force)
        ''')

    def test_existing_private_queue_finishes_old_mask_once_without_new_canonical_bonus(self):
        self.lua.execute(r'''
          local family,id="research_steel","recipe-prod-research_steel-1"
          local force=make_collected_force(1,8,{[key(family,"alternate-steel")]=true})
          local main=force.technologies[id];force.research_queue={main,force.technologies.foreign};force.current_research=main
          local queue=force.research_queue
          native_credits.on_init();set_mask(force,{},true);native_credits.on_configuration_changed()
          assert(force.research_queue==queue and force.current_research==main and force.research_progress==.42)
          close(own_contribution(force,family,"alternate-steel"),7*.17)
          advance(force,id,8,true)
          native_credits.on_research_finished({research=main,by_script=false})
          close(own_contribution(force,family,"alternate-steel"),8*.17)
          close(own_contribution(force,family,"steel-plate"),0)
          close(own_contribution(force,family,"multi-native"),0)
          native_credits.on_research_finished({research=main,by_script=false})
          close(own_contribution(force,family,"alternate-steel"),8*.17)
          advance(force,id,9,false)
          native_credits.on_research_finished({research=main,by_script=false})
          close(own_contribution(force,family,"alternate-steel"),8*.17)
          advance(force,id,10,false)
          native_credits.on_research_finished({research=main,by_script=true})
          close(own_contribution(force,family,"alternate-steel"),8*.17)
          no_foreign_write(force)
        ''')

    def test_cancelled_private_queue_cannot_be_reused_for_credit(self):
        self.lua.execute(r'''
          local family,id="research_steel","recipe-prod-research_steel-1"
          local force=make_collected_force(1,8,{[key(family,"alternate-steel")]=true})
          local main=force.technologies[id]
          force.research_queue={main,main};force.current_research=main
          native_credits.on_init();set_mask(force,{},true);native_credits.on_configuration_changed()
          force.research_queue={force.technologies.foreign};force.current_research=force.technologies.foreign
          native_credits.on_research_cancelled({force=force,research={[id]=2}})
          advance(force,id,9,false);native_credits.on_research_finished({research=main,by_script=true})
          close(own_contribution(force,family,"alternate-steel"),7*.17)
          no_foreign_write(force)
        ''')

    def test_unknown_first_paid_upgrade_refuses_before_storage_or_native_writes(self):
        self.lua.execute(r'''
          local fresh=make_collected_force(1,1,{})
          local old=make_collected_force(2,8,{},true)
          local ok,message=pcall(native_credits.on_configuration_changed,{mod_startup_settings_changed=true,
            mod_changes={["more-infinite-research"]={old_version="4.7.21003",new_version="5.0.21003"}}})
          assert(not ok and tostring(message):find("native family",1,true),"unknown old paid mask was fabricated")
          assert(storage.mir_native_credits==nil,"refusal allocated credit state")
          for _,force in ipairs({fresh,old}) do for _,state in pairs(force._states) do
            assert(state.writes.level==0 and state.writes.enabled==0,"late refusal mutated earlier native state")
          end end
        ''')

    def test_exact_502_sif_origin_preserves_only_its_authored_canonical_mask(self):
        # The production boundary requires all five published identities and
        # eleven recipes, independently authored in the preserved SIF fixture.
        published = json.loads((Path(__file__).parent / "fixtures" /
                                "sif-retained-manufacturing" / "expectations.json").read_text())
        for row in published["rows"]:
            family = json.dumps(row["family"])
            self.lua.execute(f"GROUPS[{family}]=GROUPS[{family}] or {{}}")
            for recipe in row["recipes"]:
                name = json.dumps(recipe)
                scalar = ".17" if row["family"] == "research_steel" else ".1"
                self.lua.execute(f'''local rows=GROUPS[{family}];local seen=false
                  for _,row in ipairs(rows) do if row.recipe=={name} then seen=true end end
                  if not seen then rows[#rows+1]={{recipe={name},change={scalar}}} end''')
        self.lua.execute(r'''
          reload_credits({base="2.0.77",["space-age"]="2.0.77",["space-is-fake"]="1.0.60",
            ["more-infinite-research"]="5.0.20003"},"f200")
          local family="research_steel"
          local force=make_collected_force(1,8,{[key(family,"alternate-steel")]=true})
          native_credits.on_configuration_changed({mod_startup_settings_changed=true,
            mod_changes={["more-infinite-research"]={old_version="5.0.20002",new_version="5.0.20003"}}})
          close(own_contribution(force,family,"steel-plate"),7*.17)
          close(own_contribution(force,family,"casting-steel"),7*.17)
          close(own_contribution(force,family,"alternate-steel"),0)
          close(own_contribution(force,family,"multi-native"),0)
          assert(record(force,family,"steel-plate").included==false)
          no_foreign_write(force)
        ''')

    def test_disappearing_paid_recipe_cannot_be_silently_forgotten(self):
        self.lua.execute(r'''
          local family,id="research_steel","recipe-prod-research_steel-1"
          local force=make_collected_force(1,8,{[key(family,"alternate-steel")]=true})
          native_credits.on_init();set_mask(force,{},true);native_credits.on_configuration_changed()
          local prior=record(force,family,"alternate-steel").offset
          for i=#GROUPS[family],1,-1 do if GROUPS[family][i].recipe=="alternate-steel" then table.remove(GROUPS[family],i) end end
          force.technologies["mir-native-credit-research_steel-alternate-steel-positive"]=nil
          force.technologies["mir-native-credit-research_steel-alternate-steel-negative"]=nil
          reload_credits()
          local ok,message=pcall(native_credits.on_configuration_changed,{})
          assert(not ok and tostring(message):find("native family",1,true),"missing paid route silently retired")
          assert(record(force,family,"alternate-steel").offset==prior)
          no_foreign_write(force)
        ''')

    def test_false_pending_right_survives_another_configuration_without_minting(self):
        self.lua.execute(r'''
          local family,id="research_steel","recipe-prod-research_steel-1"
          local force=make_collected_force(1,8,{})
          local main=force.technologies[id];force.research_queue={main};force.current_research=main
          native_credits.on_init()
          -- The changed private vector would pay a recipe the old work did
          -- not earn. Its literal false right must survive a second config.
          set_mask(force,{[key(family,"alternate-steel")]=true},true)
          native_credits.on_configuration_changed();native_credits.on_configuration_changed()
          assert(record(force,family,"alternate-steel").payable==false)
          advance(force,id,8,true);native_credits.on_research_finished({research=main})
          close(own_contribution(force,family,"alternate-steel"),0)
          no_foreign_write(force)
        ''')

    def test_removing_all_groups_cannot_bypass_prior_paid_state(self):
        self.lua.execute(r'''
          local family="research_steel"
          local force=make_collected_force(1,8,{[key(family,"alternate-steel")]=true})
          native_credits.on_init();set_mask(force,{},true);native_credits.on_configuration_changed()
          GROUPS={};reload_credits()
          local ok,message=pcall(native_credits.on_configuration_changed,{})
          assert(not ok and tostring(message):find("native family",1,true))
          assert(record(force,family,"alternate-steel").offset==7)
        ''')

    def test_empty_family_baseline_proves_a_later_recipe_was_not_paid(self):
        self.lua.execute(r'''
          local family,id="research_steel","recipe-prod-research_steel-1"
          local force=make_collected_force(1,8,{})
          GROUPS[family]={};reload_credits();native_credits.on_init()
          GROUPS[family]={{recipe="alternate-steel",change=.17}}
          reload_credits();set_mask(force,{[key(family,"alternate-steel")]=true})
          native_credits.on_configuration_changed()
          close(own_contribution(force,family,"alternate-steel"),0)
          assert(record(force,family,"alternate-steel").offset==-7)
        ''')

    def test_read_only_load_rebinds_only_an_existing_pending_right(self):
        self.lua.execute(r'''
          local family,id="research_steel","recipe-prod-research_steel-1"
          local force=make_collected_force(1,8,{[key(family,"alternate-steel")]=true})
          local main=force.technologies[id];force.research_queue={main};force.current_research=main
          native_credits.on_init();assert(not native_credits.needs_research_events())
          set_mask(force,{},true);native_credits.on_configuration_changed()
          local before=record(force,family,"alternate-steel")
          assert(native_credits.needs_research_events())
          reload_credits();assert(not native_credits.needs_research_events())
          local saved=game;game=nil;native_credits.on_load();game=saved
          assert(native_credits.needs_research_events() and record(force,family,"alternate-steel")==before)
          for _,state in pairs(force._states) do state.writes.level=0;state.writes.enabled=0 end
          native_credits.on_load()
          for _,state in pairs(force._states) do assert(state.writes.level==0 and state.writes.enabled==0) end
          native_credits.on_research_cancelled({force=force,research={[id]=1}})
          assert(not native_credits.needs_research_events())
        ''')

    def test_each_main_and_carrier_requires_its_own_creation_custody(self):
        self.lua.execute(r'''
          local row=require("research.native_credit_definitions").collected_descriptors(GROUPS)[1]
          for _,name in ipairs({row.main_id,row.positive_id,row.negative_id}) do
            foreign_creation=name
            local ok,message=pcall(reload_credits)
            assert(not ok and tostring(message):find("creation custody",1,true))
            assert(storage.mir_native_credits==nil)
          end
        ''')

    def test_empty_first_paid_group_cannot_invent_a_complete_old_mask(self):
        self.lua.execute(r'''
          local family,id="research_steel","recipe-prod-research_steel-1"
          local original=GROUPS
          for _,kind in ipairs({"earned","queued","detached-partial"}) do
            storage={};game.forces={};GROUPS=original;reload_credits()
            local force=make_collected_force(1,kind=="earned" and 8 or 1,{},true)
            local main=force.technologies[id]
            if kind=="queued" then force.research_queue={main};force.current_research=main
            elseif kind=="detached-partial" then main.saved_progress=.27 end
            GROUPS={[family]={}};reload_credits()
            local ok,message=pcall(native_credits.on_configuration_changed,{mod_startup_settings_changed=true,
              mod_changes={["more-infinite-research"]={old_version="4.7.21003",new_version="5.0.21003"}}})
            assert(not ok and tostring(message):find("native family",1,true),"empty first group fabricated "..kind.." mask")
            assert(storage.mir_native_credits==nil,"empty-group refusal wrote a baseline")
            for _,state in pairs(force._states) do assert(state.writes.level==0 and state.writes.enabled==0) end
          end
        ''')

    def test_empty_group_still_requires_the_named_main_and_its_creation_history(self):
        self.lua.execute(r'''
          local family,id="research_steel","recipe-prod-research_steel-1"
          local force=make_collected_force(1,1,{},true)
          GROUPS={[family]={}};foreign_creation=id
          local ok,message=pcall(reload_credits)
          assert(not ok and tostring(message):find("creation custody",1,true),"empty group bypassed main custody")
          foreign_creation=nil;reload_credits();force.technologies[id]=nil
          ok,message=pcall(native_credits.on_configuration_changed,{})
          assert(not ok and tostring(message):find("native family",1,true),"empty group ignored a missing main")
          assert(storage.mir_native_credits==nil)
        ''')

    def test_credit_parse_does_not_import_the_inactive_sif_adapter(self):
        self.lua.execute(r'''
          local name="compatibility.modern_catalogue.sif_retained"
          package.loaded[name]=nil;package.preload[name]=function()error("inactive SIF adapter imported")end
          reload_credits()
          assert(package.loaded[name]==nil)
          local definitions=require("research.native_credit_definitions")
          local first=definitions.published_sif_contracts()
          first[1].recipes[1][1]="tampered"
          assert(definitions.published_sif_contracts()[1].recipes[1][1]=="casting-low-density-structure")
          local sets=definitions.published_sif_paid_recipe_sets();sets.research_steel["steel-plate"]=nil
          assert(definitions.published_sif_paid_recipe_sets().research_steel["steel-plate"])
        ''')

    def test_configuration_counts_the_native_queue_once_per_force_not_per_recipe(self):
        self.lua.execute(r'''
          local family,id="research_steel","recipe-prod-research_steel-1"
          local force=make_collected_force(1,8,{[key(family,"alternate-steel")]=true})
          local main=force.technologies[id]
          native_credits.on_init()
          local scans=0
          force.research_queue=setmetatable({main,main,force.technologies.foreign},{__ipairs=function(values)
            scans=scans+1
            return function(rows,index)index=index+1;if rows[index] then return index,rows[index] end end,values,0
          end})
          force.current_research=main;set_mask(force,{},true)
          native_credits.on_configuration_changed()
          assert(scans==1,"native queue was scanned once for every recipe")
          assert(record(force,family,"alternate-steel").pending==2)
          no_foreign_write(force)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

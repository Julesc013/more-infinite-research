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
import test_bootstrap as bootstrap_fixture


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

    def _plain_beta_base(self, edition="f210", extra=False):
        # These five one-recipe public masks are independently retained in all
        # six published 5.0.0-5.0.2 Base ZIP observations (18 controlled cases).
        recipes = {"research_low_density_structure": "low-density-structure",
                   "research_plastic": "plastic-bar", "research_processing_unit": "processing-unit",
                   "research_rocket_fuel": "rocket-fuel", "research_steel": "steel-plate"}
        self.lua.globals().base_edition = edition
        self.lua.execute('GROUPS={};published_base_mask={}')
        for family, recipe in recipes.items():
            self.lua.globals().base_family = family
            self.lua.globals().base_recipe = recipe
            self.lua.execute('''
              GROUPS[base_family]={{recipe=base_recipe,change=base_family=="research_steel" and .17 or .1}}
              published_base_mask[key(base_family,base_recipe)]=true
            ''')
        if extra:
            self.lua.execute('''
              GROUPS.research_steel[2]={recipe="new-unpaid-steel",change=.17}
              published_base_mask[key("research_steel","new-unpaid-steel")]=true
            ''')
        self.lua.execute('''
          local f200=base_edition=="f200"
          BASE_ACTIVE={base=f200 and "2.0.77" or "2.1.23",
            ["more-infinite-research"]=f200 and "5.0.20003" or "5.0.21003"}
          reload_credits(BASE_ACTIVE,base_edition)
        ''')

    def test_plain_base_six_published_beta_origins_keep_original_paid_masks_and_work(self):
        for edition, prefix in (("f200", "5.0.200"), ("f210", "5.0.210")):
            for patch in ("00", "01", "02"):
                with self.subTest(edition=edition, patch=patch):
                    self.setUp()
                    self._plain_beta_base(edition, extra=True)
                    self.lua.globals().old_base_beta = prefix + patch
                    self.lua.execute('''
                      local force=make_collected_force(1,8,published_base_mask,false)
                      local main=force.technologies["recipe-prod-research_steel-1"]
                      main.saved_progress=.27;force.research_queue={main,force.technologies.foreign}
                      force.current_research=main;local queue=force.research_queue
                      native_credits.on_configuration_changed({mod_startup_settings_changed=false,
                        mod_changes={["more-infinite-research"]={old_version=old_base_beta,
                          new_version=BASE_ACTIVE["more-infinite-research"]}}})
                      for family,recipes in pairs(GROUPS) do
                        close(own_contribution(force,family,recipes[1].recipe),7*recipes[1].change)
                        assert(record(force,family,recipes[1].recipe).included==true)
                      end
                      close(own_contribution(force,"research_steel","new-unpaid-steel"),0)
                      assert(record(force,"research_steel","new-unpaid-steel").offset==-7,
                        "new candidate output was mistaken for the historical paid mask")
                      assert(force.research_queue==queue and force.current_research==main
                        and main.saved_progress==.27 and force.research_progress==.42)
                      no_foreign_write(force)
                    ''')

    def test_plain_beta_base_reader_refuses_changed_unknown_or_foreign_inputs_before_writes(self):
        for opponent in ("startup", "added-provider", "removed-provider", "engine-change",
                         "unknown-beta", "wrong-edition", "private-main", "incomplete-old-mask"):
            with self.subTest(opponent=opponent):
                self.setUp()
                self._plain_beta_base()
                self.lua.globals().opponent = opponent
                self.lua.execute('''
                  local changes={["more-infinite-research"]={old_version="5.0.21002",new_version="5.0.21003"}}
                  local changed=opponent=="startup"
                  if opponent=="added-provider" then BASE_ACTIVE.foreign="1.0.0" end
                  if opponent=="removed-provider" then changes.foreign={old_version="1.0.0"} end
                  if opponent=="engine-change" then changes.base={old_version="2.1.22",new_version="2.1.23"} end
                  if opponent=="unknown-beta" then changes["more-infinite-research"].old_version="5.0.21003" end
                  if opponent=="wrong-edition" then changes["more-infinite-research"].old_version="5.0.20002" end
                  if opponent=="incomplete-old-mask" then GROUPS.research_plastic=nil end
                  reload_credits(BASE_ACTIVE,"f210")
                  local force=make_collected_force(1,8,published_base_mask,opponent=="private-main")
                  local ok,message=pcall(native_credits.on_configuration_changed,
                    {mod_startup_settings_changed=changed,mod_changes=changes})
                  assert(not ok and tostring(message):find("native family",1,true),"unsafe baseline admitted")
                  assert(storage.mir_native_credits==nil,"refusal allocated a baseline")
                  for _,state in pairs(force._states) do assert(state.writes.level==0 and state.writes.enabled==0) end
                  no_foreign_write(force)
                ''')

    def _published_m4_base(self, origin="f200"):
        # Read preserved published observations, never today's declarations.
        # The protected 4.7.20003 Base hop retains these five public identities;
        # modern-f210-470 independently records the same one-recipe Base mask.
        inventory = json.loads((Path(__file__).resolve().parents[1] / "spec" / "inventory" /
                                ("modern-" + origin + "-470.json")).read_text())
        profile = next(p for p in inventory["profiles"] if p["id"] == "base-" + origin)
        families = ("low_density_structure", "plastic", "processing_unit", "rocket_fuel", "steel")
        additions = profile["published_output"]["data"]["additions"]
        self.lua.execute('GROUPS={};published_base_mask={}')
        for family in families:
            row = next(r["row"] for r in additions if r["type"] == "technology"
                       and r["name"] == "recipe-prod-research_" + family + "-1")
            self.assertEqual(len(row["effects"]), 1)
            effect = row["effects"][0]
            self.assertEqual(effect["type"], "change-recipe-productivity")
            self.lua.globals().base_family = "research_" + family
            self.lua.globals().base_recipe = effect["recipe"]
            self.lua.globals().base_change = effect["change"]
            self.lua.execute('''
              GROUPS[base_family]={{recipe=base_recipe,change=base_change}}
              published_base_mask[key(base_family,base_recipe)]=true
            ''')
        self.lua.execute('''
          GROUPS.research_steel[2]={recipe="new-unpaid-steel",change=.1}
          published_base_mask[key("research_steel","new-unpaid-steel")]=true
          BASE_ACTIVE={base="2.1.23",["more-infinite-research"]="5.0.21003"}
          reload_credits(BASE_ACTIVE,"f210")
        ''')

    def test_published_m4_base_same_engine_and_exact_hop_preserve_only_old_paid_mask(self):
        for origin, destination in (("f210", "5.0.21003"), ("f200", "5.0.21003"), ("f200", "5.0.21004")):
            with self.subTest(origin=origin, destination=destination):
                self.setUp()
                self._published_m4_base(origin)
                self.lua.globals().cross_engine = origin == "f200"
                self.lua.globals().destination = destination
                self.lua.execute('''
                  BASE_ACTIVE["more-infinite-research"]=destination;reload_credits(BASE_ACTIVE,"f210")
                  local force=make_collected_force(1,8,published_base_mask,false)
                  local main=force.technologies["recipe-prod-research_steel-1"]
                  main.saved_progress=.27;force.research_queue={main,force.technologies.foreign}
                  force.current_research=main;local queue=force.research_queue
                  local changes={["more-infinite-research"]={old_version=cross_engine and "4.7.20003" or "4.7.21003",
                    new_version=destination}}
                  if cross_engine then changes.base={old_version="2.0.77",new_version="2.1.23"} end
                  native_credits.on_configuration_changed({mod_startup_settings_changed=false,mod_changes=changes})
                  for family,recipes in pairs(GROUPS) do
                    close(own_contribution(force,family,recipes[1].recipe),7*recipes[1].change)
                    assert(record(force,family,recipes[1].recipe).offset==0)
                  end
                  close(own_contribution(force,"research_steel","new-unpaid-steel"),0)
                  assert(record(force,"research_steel","new-unpaid-steel").offset==-7,
                    "current output fabricated old earning rights")
                  assert(force.research_queue==queue and force.current_research==main
                    and main.saved_progress==.27 and force.research_progress==.42)
                  no_foreign_write(force)
                ''')

    def test_published_m4_base_hop_refuses_unproven_inputs_before_all_mir_writes(self):
        opponents = ("startup", "unknown-startup", "added-provider", "unchanged-provider", "removed-provider",
                     "observer", "unknown-origin", "wrong-destination", "wrong-current-version", "missing-engine",
                     "other-source-patch", "older-destination-patch", "future-destination-patch", "future-engine",
                     "wrong-active-engine", "future-minor", "same-engine-future-patch", "inconsistent-same-engine",
                     "private-main", "incomplete-old-mask")
        for full_bootstrap in (False, True):
            for opponent in opponents:
                with self.subTest(bootstrap=full_bootstrap, opponent=opponent):
                    self.setUp()
                    self._published_m4_base()
                    if full_bootstrap:
                        bootstrap_fixture.BootstrapTests().setUp(self.lua)
                        self.lua.execute('''
                          local real_credits=native_credits
                          install_modules(false,false,false,true);install_runtime(nil,BASE_ACTIVE);game.forces={}
                          package.preload["runtime.native_credits"]=function()return real_credits end
                          load_control()
                        ''')
                    self.lua.globals().opponent = opponent
                    self.lua.globals().full_bootstrap = full_bootstrap
                    self.lua.execute('''
                      local changes={base={old_version="2.0.77",new_version="2.1.23"},
                        ["more-infinite-research"]={old_version="4.7.20003",new_version="5.0.21003"}}
                      local changed=false
                      if opponent=="startup" then changed=true end
                      if opponent=="unknown-startup" then changed=nil end
                      if opponent=="added-provider" or opponent=="unchanged-provider" then
                        BASE_ACTIVE.ExpandedProductivityResearch="1.0.0"
                      end
                      if opponent=="added-provider" then changes.ExpandedProductivityResearch={new_version="1.0.0"} end
                      if opponent=="removed-provider" then changes.ExpandedProductivityResearch={old_version="1.0.0"} end
                      if opponent=="observer" then BASE_ACTIVE["mir-fixture-observer"]="0.1.0" end
                      if opponent=="unknown-origin" then changes["more-infinite-research"].old_version="4.7.20004" end
                      if opponent=="wrong-destination" then changes["more-infinite-research"].new_version="5.0.21004" end
                      if opponent=="wrong-current-version" then
                        BASE_ACTIVE["more-infinite-research"]="5.0.20003"
                        changes["more-infinite-research"].new_version="5.0.20003"
                      end
                      if opponent=="missing-engine" then changes.base=nil end
                      if opponent=="other-source-patch" then changes.base.old_version="2.0.76" end
                      if opponent=="older-destination-patch" then changes.base.new_version="2.1.22";BASE_ACTIVE.base="2.1.22" end
                      if opponent=="future-destination-patch" then changes.base.new_version="2.1.24";BASE_ACTIVE.base="2.1.24" end
                      if opponent=="future-engine" then changes.base.new_version="2.2.0";BASE_ACTIVE.base="2.2.0" end
                      if opponent=="wrong-active-engine" then BASE_ACTIVE.base="2.1.24" end
                      if opponent=="future-minor" then
                        BASE_ACTIVE["more-infinite-research"]="5.1.21000"
                        changes["more-infinite-research"].new_version="5.1.21000"
                      end
                      if opponent=="same-engine-future-patch" then
                        changes["more-infinite-research"].old_version="4.7.21003"
                        changes.base=nil;BASE_ACTIVE.base="2.1.24"
                      end
                      if opponent=="inconsistent-same-engine" then
                        changes["more-infinite-research"].old_version="4.7.21003"
                        changes.base.old_version="2.0.77";changes.base.new_version="2.0.77"
                      end
                      if opponent=="incomplete-old-mask" then GROUPS.research_plastic=nil end
                      reload_credits(BASE_ACTIVE,"f210")
                      local fresh=make_collected_force(1,1,{},false)
                      local force=make_collected_force(2,8,published_base_mask,opponent=="private-main")
                      local event={mod_startup_settings_changed=changed,mod_changes=changes}
                      local callback=full_bootstrap and handlers.configuration or native_credits.on_configuration_changed
                      local ok,message=pcall(callback,event)
                      assert(not ok and tostring(message):find("native family",1,true),"unproven hop admitted: "..opponent)
                      assert(next(storage)==nil,"refusal wrote MIR storage")
                      for _,f in ipairs({fresh,force}) do
                        for _,state in pairs(f._states) do assert(state.writes.level==0 and state.writes.enabled==0,
                          "refusal mutated native state") end
                        no_foreign_write(f)
                      end
                      if full_bootstrap then
                        assert(lifecycle_calls.configuration==nil and library_calls.configuration==nil
                          and module_credit_calls.preflight==nil and cannon_credit_calls.preflight==nil
                          and scripted_calls.configuration==nil,"bootstrap wrote before real credit refusal")
                      end
                    ''')

    def _same_engine_unknown_paid_mask(self, opponent):
        self._published_m4_base("f210")
        self.lua.globals().unchanged_mod = opponent
        self.lua.execute('''
          BASE_ACTIVE[unchanged_mod]="1.0.0"
          if unchanged_mod=="space-age" then BASE_ACTIVE[unchanged_mod]="2.1.23" end
          reload_credits(BASE_ACTIVE,"f210")
          same_engine_event={mod_startup_settings_changed=false,
            mod_changes={["more-infinite-research"]={old_version="4.7.21003",new_version="5.0.21003"}}}
          function assert_unknown_mask_refuses(callback)
            local fresh=make_collected_force(1,1,{},false)
            local force=make_collected_force(2,8,published_base_mask,false)
            local main=force.technologies["recipe-prod-research_steel-1"]
            main.saved_progress=.27;force.research_queue={main,force.technologies.foreign}
            force.current_research=main;local queue=force.research_queue
            local ok,message=pcall(callback,same_engine_event)
            assert(not ok and tostring(message):find("unknown first paid mask",1,true),
              "unchanged "..unchanged_mod.." fabricated a first paid mask: "..tostring(message))
            assert(next(storage)==nil,"refusal wrote MIR storage")
            for _,f in ipairs({fresh,force}) do
              for _,state in pairs(f._states) do
                assert(state.writes.level==0 and state.writes.enabled==0,"refusal mutated native state")
              end
              no_foreign_write(f)
            end
            assert(force.research_queue==queue and force.current_research==main
              and main.saved_progress==.27 and force.research_progress==.42,"refusal changed invested work")
          end
        ''')

    def test_same_engine_unchanged_mods_cannot_prove_a_first_paid_mask(self):
        for opponent in ("mir-fixture-observer", "ExpandedProductivityResearch", "space-age"):
            with self.subTest(opponent=opponent):
                self.setUp()
                self._same_engine_unknown_paid_mask(opponent)
                self.lua.execute('assert_unknown_mask_refuses(native_credits.preflight_family_transition)')

    def _add_published_sif_recipients(self):
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

    def test_exact_502_sif_origin_preserves_only_its_authored_canonical_mask(self):
        self._add_published_sif_recipients()
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

    def test_unknown_zero_completed_private_investment_cannot_invent_a_baseline(self):
        for kind in ("queued", "detached-partial"):
            with self.subTest(kind=kind):
                self.setUp()
                self.lua.globals().investment_kind = kind
                self.lua.execute(r'''
                  local id="recipe-prod-research_steel-1"
                  local force=make_collected_force(1,1,{},true)
                  local main=force.technologies[id]
                  if investment_kind=="queued" then force.research_queue={main};force.current_research=main
                  else main.saved_progress=.27 end
                  local ok,message=pcall(native_credits.on_configuration_changed,{mod_startup_settings_changed=true,
                    mod_changes={["more-infinite-research"]={old_version="4.7.21003",new_version="5.0.21003"}}})
                  assert(not ok and tostring(message):find("native family",1,true),"zero completed discarded original investment")
                  assert(storage.mir_native_credits==nil,"unknown invested baseline wrote storage")
                  for _,state in pairs(force._states) do assert(state.writes.level==0 and state.writes.enabled==0) end
                  assert(main.saved_progress==(investment_kind=="detached-partial" and .27 or nil))
                  no_foreign_write(force)
                ''')

    def test_known_502_sif_zero_completed_queue_keeps_its_canonical_right(self):
        self._add_published_sif_recipients()
        self.lua.execute(r'''
          reload_credits({base="2.0.77",["space-age"]="2.0.77",["space-is-fake"]="1.0.60",
            ["more-infinite-research"]="5.0.20003"},"f200")
          local family,id="research_steel","recipe-prod-research_steel-1"
          local force=make_collected_force(1,1,{},true)
          local main=force.technologies[id]
          force.research_queue={main,main,force.technologies.foreign};force.current_research=main
          local queue=force.research_queue
          native_credits.on_configuration_changed({mod_startup_settings_changed=true,
            mod_changes={["more-infinite-research"]={old_version="5.0.20002",new_version="5.0.20003"}}})
          assert(record(force,family,"steel-plate").payable==true,"known first queue lost canonical reward")
          assert(record(force,family,"steel-plate").pending==2 and native_credits.needs_research_events())
          for completed=1,2 do
            advance(force,id,completed,true);native_credits.on_research_finished({research=main})
            close(own_contribution(force,family,"steel-plate"),completed*.17)
            close(own_contribution(force,family,"casting-steel"),completed*.17)
            close(own_contribution(force,family,"alternate-steel"),0)
          end
          advance(force,id,3,true);native_credits.on_research_finished({research=main})
          close(own_contribution(force,family,"steel-plate"),2*.17)
          assert(not native_credits.needs_research_events())
          assert(force.research_queue==queue and force.current_research==main and force.research_progress==.42)
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
          local contracts=require("research.native_credit_contracts")
          local base=contracts.published_beta_base_paid_recipe_sets()
          base.research_steel["steel-plate"]=nil;base.research_plastic=nil
          local again=contracts.published_beta_base_paid_recipe_sets()
          assert(again.research_steel["steel-plate"] and again.research_plastic["plastic-bar"])
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


    def test_force_merge_retains_destination_rights_and_discards_source_research(self):
        # LuaGameScript.merge_forces retains destination technologies/bonuses;
        # it does not combine source research. Native engine runs remain required.
        cases = [(kind, earned) for kind in ("empty", "earned", "signed", "queued", "partial", "cancelled")
                 for earned in (0, 7)]
        for source_kind, earned in cases:
            with self.subTest(source=source_kind, destination_earned=earned):
                self.setUp()
                self._add_published_sif_recipients()
                self.lua.globals().source_kind = source_kind
                self.lua.globals().destination_earned = earned
                self.lua.execute('''
                  reload_credits({base="2.0.77",["space-age"]="2.0.77",["space-is-fake"]="1.0.60",
                    ["more-infinite-research"]="5.0.20003"},"f200")
                  local family,id="research_steel","recipe-prod-research_steel-1"
                  local destination=make_collected_force(1,destination_earned+1,{},true)
                  local source=make_collected_force(17,source_kind=="earned" and 8 or 1,{},true)
                  local main,source_main=destination.technologies[id],source.technologies[id]
                  destination.research_queue={main,main,destination.technologies.foreign}
                  destination.current_research=main;main.saved_progress=.27
                  if source_kind=="queued" then source.research_queue={source_main};source.current_research=source_main end
                  if source_kind=="partial" then source_main.saved_progress=.19 end
                  native_credits.on_configuration_changed({mod_startup_settings_changed=true,
                    mod_changes={["more-infinite-research"]={old_version="5.0.20002",new_version="5.0.20003"}}})
                  if source_kind=="signed" then
                    for _,d in ipairs(native_credit_definitions.collected_descriptors(GROUPS)) do
                      if d.family==family and d.recipe=="steel-plate" then
                        source._states[d.positive_id].level=6;source._states[d.negative_id].level=4
                        record(source,family,"steel-plate").offset=2
                      end
                    end
                  end
                  assert(record(destination,family,"steel-plate").payable==true)
                  assert(record(destination,family,"alternate-steel").payable==false)
                  local queue=destination.research_queue
                  local order={};for i,t in ipairs(queue) do order[i]=t.name end
                  local source_index=source.index
                  game.forces[source_index]=nil;source.valid=false -- native post-merge invalidation
                  native_credits.on_forces_merged({source_index=source_index,destination=destination})
                  assert(storage.mir_native_credits.forces[source_index]==nil
                    and storage.mir_native_credits.families[source_index]==nil,"source history survived native destruction")
                  assert(record(destination,family,"steel-plate").payable==true
                    and record(destination,family,"steel-plate").pending==2,"destination pending right was reset")
                  assert(record(destination,family,"alternate-steel").payable==false
                    and record(destination,family,"alternate-steel").pending==2,"literal-false right was changed")
                  assert(native_credits.needs_research_events())
                  native_credits.on_load();assert(native_credits.needs_research_events(),"load lost pending subscription")
                  close(own_contribution(destination,family,"steel-plate"),destination_earned*.17)
                  local completions=2
                  if source_kind=="cancelled" then
                    native_credits.on_research_cancelled({force=destination,research={[id]=1}})
                    completions=1
                    assert(record(destination,family,"steel-plate").pending==1)
                  end
                  for completed=1,completions do
                    advance(destination,id,destination_earned+completed,true);native_credits.on_research_finished({research=main})
                    close(own_contribution(destination,family,"steel-plate"),(destination_earned+completed)*.17)
                    close(own_contribution(destination,family,"casting-steel"),(destination_earned+completed)*.17)
                    close(own_contribution(destination,family,"alternate-steel"),0)
                  end
                  assert(not native_credits.needs_research_events())
                  advance(destination,id,destination_earned+completions+1,true);native_credits.on_research_finished({research=main})
                  close(own_contribution(destination,family,"steel-plate"),(destination_earned+completions)*.17)
                  assert(destination.research_queue==queue and #queue==#order)
                  for i,t in ipairs(queue) do assert(t.name==order[i],"destination queue order changed") end
                  assert(destination.current_research==main and destination.research_progress==.42 and main.saved_progress==.27)
                  no_foreign_write(destination)
                ''')

    def test_force_merge_refuses_inconsistent_destination_before_any_mir_write(self):
        for broken in ("offset", "record", "history", "completed"):
            with self.subTest(broken=broken):
                self.setUp()
                self._add_published_sif_recipients()
                self.lua.globals().broken = broken
                self.lua.execute('''
                  reload_credits({base="2.0.77",["space-age"]="2.0.77",["space-is-fake"]="1.0.60",
                    ["more-infinite-research"]="5.0.20003"},"f200")
                  local family,id="research_steel","recipe-prod-research_steel-1"
                  local destination=make_collected_force(1,1,{},true)
                  local source=make_collected_force(17,1,{},true)
                  local main=destination.technologies[id]
                  destination.research_queue={main};destination.current_research=main
                  native_credits.on_configuration_changed({mod_startup_settings_changed=true,
                    mod_changes={["more-infinite-research"]={old_version="5.0.20002",new_version="5.0.20003"}}})
                  local state=storage.mir_native_credits
                  if broken=="offset" then record(destination,family,"steel-plate").offset=7 end
                  if broken=="record" then state.forces[1][key(family,"steel-plate")]=nil end
                  if broken=="history" then state.families[1][family]=nil end
                  if broken=="completed" then record(destination,family,"steel-plate").completed=1 end
                  local before={}
                  for index,force in ipairs({destination,source}) do
                    before[index]={}
                    for name,s in pairs(force._states) do before[index][name]={s.writes.level,s.writes.enabled} end
                  end
                  local destination_records,source_records=state.forces[1],state.forces[17]
                  local history=state.families[1]
                  local ok,message=pcall(native_credits.on_forces_merged,{source_index=17,destination=destination})
                  assert(not ok and tostring(message):find("native family",1,true),"inconsistent destination admitted")
                  assert(state.forces[1]==destination_records and state.forces[17]==source_records
                    and state.families[1]==history,"refusal cleared existing history")
                  for index,force in ipairs({destination,source}) do
                    for name,s in pairs(force._states) do
                      assert(s.writes.level==before[index][name][1] and s.writes.enabled==before[index][name][2],
                        "late merge refusal mutated native state")
                    end
                  end
                  no_foreign_write(destination)
                ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

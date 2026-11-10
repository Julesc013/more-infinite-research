"""Draft worker native-owner constructors; host tables do not qualify native debit effects."""
import argparse
from pathlib import Path
import sys
import unittest
import test_worker_storage_continuation as worker_pipeline
from worker_storage_recovery_fixture import expected_private_worker_row


class WorkerNativeOwnerDataTests(unittest.TestCase):
    def pipeline(self, target="f210", rows=None, changes=None, extra_mods=None, before=None):
        worker_pipeline.LuaRuntime = LuaRuntime
        case = worker_pipeline.WorkerStorageContinuationTests()
        lua = case.stage(rows, target, changes=changes, extra_mods=extra_mods)
        if before:
            lua.execute(before)
        case.pipeline(lua)
        return case, lua

    def runtime_catalogue(self, case, lua):
        case.runtime(lua)
        lua.execute('''
          for _,name in ipairs({"mir-worker-storage-default-4","mir-worker-storage-head-4"})do
            local row=data.raw.technology[name]
            if row then native_prototypes[name]={name=name,level=row.level,
              max_level=row.max_level=="infinite" and 4294967295 or row.max_level,
              effects=row.effects,prerequisites=row.prerequisites}end
          end
        ''')

    def stage(self, target="f210"):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = (Path(__file__).resolve().parents[1] / "source").as_posix()
        lua.globals().selected_target = target
        lua.execute(r'''
          package.path=player_root.."/?.lua;"..player_root.."/?/init.lua";package.cpath=""
          package.loaded["platform.target"]={id=selected_target}
          data=setmetatable({}, {__index=function()error("constructor read data")end,
            __newindex=function()error("constructor wrote data")end})
          owner=require("research.worker_storage_recovery")
          function authored()
            return {type="technology",name="worker-robots-storage-4",level=4,max_level="infinite",
              hidden=true,enabled=false,visible_when_disabled=false,upgrade=true,order="a[worker]",
              icons={{icon="__base__/graphics/technology/worker-robots-storage.png",icon_size=256,
                tint={r=.25,g=.5,b=.75,a=1}}},
              localised_name={"technology-name.worker-robots-storage"},
              localised_description={"", "owned description ", {"technology-name.worker-robots-storage"}},
              prerequisites={"worker-robots-storage-3","production-science-pack","utility-science-pack"},
              effects={{type="worker-robot-storage",modifier=1,hidden=false,infer_icon=false}},
              ignore_tech_cost_multiplier=true,
              unit={count_formula="675*1.5^(L-4)",time=60,
                ingredients={{"automation-science-pack",1},{"logistic-science-pack",2},
                  {"chemical-science-pack",1},{"production-science-pack",1},{"utility-science-pack",1}}}}
          end
          function deep(value)
            if type(value)~="table"then return value end
            local out={};for key,item in pairs(value)do out[key]=deep(item)end;return out
          end
          function same(a,b)
            assert(type(a)==type(b),"different type")
            if type(a)~="table"then assert(a==b,"different scalar");return end
            for key,value in pairs(a)do same(value,b[key])end
            for key in pairs(b)do assert(a[key]~=nil,"extra field")end
          end
          function native(row)
            local prerequisites={}
            for _,name in ipairs(row.prerequisites or {})do prerequisites[name]={name=name}end
            return {name=row.name,level=row.level,max_level=row.max_level=="infinite" and 4294967295 or row.max_level,
              effects={{type=row.effects[1].type,modifier=row.effects[1].modifier,hidden=row.effects[1].hidden}},
              prerequisites=prerequisites,research_unit_count_formula=row.unit.count_formula,
              research_unit_count=row.unit.count,research_unit_energy=row.unit.time*60,
              research_unit_ingredients=(function()
                local ingredients={}
                for i,v in ipairs(row.unit.ingredients)do ingredients[i]={name=v[1],amount=v[2]}end
                return ingredients
              end)(),ignore_tech_cost_multiplier=row.ignore_tech_cost_multiplier==true}
          end
          function refused(source, id)
            local before=deep(source)
            assert(not pcall(owner.ordinary,source,id or owner.ordinary_provider_id))
            assert(not pcall(owner.debit,source))
            assert(not pcall(owner.default_owner,source))
            assert(not pcall(owner.head_debit,source))
            same(source,before)
          end
        ''')
        return lua

    def test_exact_distinct_authored_identities(self):
        lua = self.stage()
        lua.execute(r'''
          assert(owner.id=="mir-worker-storage-preservation-4" and owner.canonical=="worker-robots-storage-4")
          assert(owner.ordinary_default_id=="mir-worker-storage-default-4")
          assert(owner.ordinary_provider_id=="mir-worker-storage-provider-4")
          assert(owner.provider_debit_id=="mir-worker-storage-provider-debit-4")
          assert(owner.head_id=="mir-worker-storage-head-4")
          local seen={}
          for _,id in ipairs({owner.id,owner.canonical,owner.ordinary_default_id,
              owner.ordinary_provider_id,owner.provider_debit_id,owner.head_id})do
            assert(not seen[id]);seen[id]=true
          end
        ''')

    def test_ordinary_provider_preserves_complete_authored_contract_both_targets(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.stage(target).execute(r'''
                  local source=authored();local before=deep(source)
                  for _,id in ipairs({owner.ordinary_provider_id})do
                    local expected=deep(before)
                    expected.name,expected.hidden=id,false
                    same(owner.ordinary(source,id),expected)
                  end
                  same(source,before)
                ''')

    def test_debit_changes_only_identity_visibility_and_exact_effect_sign(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.stage(target).execute(r'''
                  local source=authored();local before=deep(source);local expected=deep(source)
                  expected.name="mir-worker-storage-provider-debit-4"
                  expected.hidden,expected.enabled,expected.visible_when_disabled=true,false,false
                  expected.effects[1].modifier=-1
                  same(owner.debit(source),expected);same(source,before)
                  assert(owner.debit(source).level==4 and owner.debit(source).max_level=="infinite")
                ''')

    def test_default_owner_keeps_absolute_level_prices_and_complete_source_contract(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.stage(target).execute(r'''
                  for _,modifier in ipairs({0,1,2})do
                    local source=authored();source.effects[1].modifier=modifier;local before=deep(source)
                    local expected=deep(source)
                    expected.name="mir-worker-storage-default-4";expected.level=4;expected.hidden=false
                    local tail=owner.default_owner(source);same(tail,expected);same(source,before)
                    assert(tail.max_level=="infinite" and tail.enabled==false and tail.visible_when_disabled==false)
                    assert(tail.unit.count_formula=="675*1.5^(L-4)")
                    assert(owner.matches_default_owner(native(source),native(tail)))
                    for level=4,12 do
                      local source_price=675*1.5^(level-4)
                      local tail_price=assert(load("return "..tail.unit.count_formula:gsub("L",tostring(level))))()
                      assert(source_price==tail_price)
                    end
                    tail.unit.ingredients[1][2]=99;tail.prerequisites[1]="changed"
                    same(source,before)
                  end
                ''')

    def test_head_debit_is_negative_finite_four_with_exact_first_source_science(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.stage(target).execute(r'''
                  for _,modifier in ipairs({0,1,2})do
                    local source=authored();source.effects[1].modifier=modifier
                    source.unit.ingredients[1]={"logistic-science-pack",3};local before=deep(source)
                    local expected=deep(source)
                    expected.name="mir-worker-storage-head-4";expected.level=4;expected.max_level=4
                    expected.hidden,expected.enabled,expected.visible_when_disabled=true,false,false
                    expected.effects[1].modifier=modifier==0 and 0 or -modifier;expected.prerequisites={}
                    expected.unit={count=1,time=1,ingredients={{"logistic-science-pack",1}}}
                    local gate=owner.head_debit(source);same(gate,expected);same(source,before)
                    assert(gate.level==gate.max_level and gate.effects[1].modifier==-modifier)
                    gate.unit.ingredients[1][1]="changed";gate.effects[1].modifier=99
                    same(source,before)
                  end
                ''')

    def test_head_and_full_owner_preserve_native_contribution_without_double_counting(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.stage(target).execute(r'''
                  for _,modifier in ipairs({0,1,2})do
                    local source=authored();source.effects[1].modifier=modifier
                    local tail=owner.default_owner(source);local gate=owner.head_debit(source)
                    assert((4-4)*modifier==0) -- No paid head: gate remains false; no tail grant.
                    for next_level=5,25 do
                      local old_paid=(next_level-4)*modifier
                      local public_head=modifier
                      local stable_tail=(next_level-4)*tail.effects[1].modifier
                      local gate_contribution=gate.effects[1].modifier
                      assert(old_paid==public_head+stable_tail+gate_contribution)
                    end
                  end
                ''')

    def test_tail_native_comparison_rejects_every_unapproved_contract_or_start_boundary(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.stage(target).execute(r'''
                  local source=authored();local tail=owner.default_owner(source)
                  local before_source,before_tail=native(source),native(tail)
                  for _,change in ipairs({
                    function(s,t)t.level=5 end,function(s,t)t.max_level=5 end,
                    function(s,t)s.level=5 end,function(s,t)s.max_level=4 end,
                    function(s,t)t.name=owner.ordinary_provider_id end,
                    function(s,t)t.effects[1].modifier=2 end,
                    function(s,t)t.research_unit_count_formula="675*1.5^(L-5)"end,
                    function(s,t)t.research_unit_energy=1 end,
                    function(s,t)t.research_unit_ingredients[1].amount=2 end,
                    function(s,t)t.ignore_tech_cost_multiplier=false end,
                    function(s,t)t.prerequisites[owner.head_id]={name=owner.head_id}end,
                    function(s,t)t.prerequisites[owner.canonical]={name=owner.canonical}end,
                    function(s,t)t.prerequisites["worker-robots-storage-3"]=nil end,
                    function(s,t)t.prerequisites.extra={name="extra"}end})do
                    local s,t=deep(before_source),deep(before_tail);change(s,t)
                    local saved_s,saved_t=deep(s),deep(t)
                    assert(not owner.matches_default_owner(s,t));same(s,saved_s);same(t,saved_t)
                  end
                  local bad=authored();bad.name="provider-authored-4"
                  assert(not pcall(owner.default_owner,bad) and not pcall(owner.head_debit,bad))
                  assert(not pcall(owner.ordinary,authored(),owner.ordinary_default_id))
                ''')

    def test_every_nested_output_is_detached_from_source_and_other_outputs(self):
        lua = self.stage()
        lua.execute(r'''
          local source=authored();local expected=deep(source)
          local a=owner.default_owner(source)
          local b=owner.ordinary(source,owner.ordinary_provider_id);local d=owner.debit(source)
          a.unit.ingredients[1][2]=99;a.unit.time=2;a.prerequisites[1]="changed"
          a.effects[1].modifier=123;a.icons[1].tint.r=1;a.localised_description[3][1]="changed"
          same(source,expected)
          assert(b.unit.ingredients[1][2]==1 and d.unit.ingredients[1][2]==1)
          assert(b.effects[1].modifier==1 and d.effects[1].modifier==-1)
          source.unit.ingredients[2][2]=777;source.icons[1].tint.g=1
          assert(b.unit.ingredients[2][2]==2 and d.icons[1].tint.g==.5)
          assert(a.unit~=b.unit and b.unit~=d.unit and a.icons[1]~=b.icons[1])
        ''')

    def test_configured_zero_and_two_effects_keep_exact_native_scalar_and_debit(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.stage(target).execute(r'''
                  for _,modifier in ipairs({0,2})do
                    local source=authored();source.effects[1].modifier=modifier
                    local before=deep(source)
                    for _,id in ipairs({owner.ordinary_provider_id})do
                      local expected=deep(source);expected.name,expected.hidden=id,false
                      local row=owner.ordinary(source,id);same(row,expected)
                      assert(row.effects[1].modifier==modifier)
                    end
                    local expected=deep(source)
                    expected.name=owner.provider_debit_id
                    expected.hidden,expected.enabled,expected.visible_when_disabled=true,false,false
                    expected.effects[1].modifier=modifier==0 and 0 or -modifier
                    local debit=owner.debit(source);same(debit,expected)
                    assert(debit.effects[1].modifier+modifier==0)
                    if modifier==0 then assert(1/debit.effects[1].modifier==math.huge)end
                    same(source,before)
                  end
                ''')

    def test_fixed_count_and_optional_prerequisites_remain_exact(self):
        lua = self.stage()
        lua.execute(r'''
          local source=authored();source.unit.count_formula=nil;source.unit.count=675
          source.prerequisites=nil;source.ignore_tech_cost_multiplier=false
          local a=owner.ordinary(source,owner.ordinary_provider_id);local d=owner.debit(source)
          assert(a.unit.count==675 and a.unit.count_formula==nil and a.prerequisites==nil)
          assert(d.unit.count==675 and d.unit.time==60 and d.ignore_tech_cost_multiplier==false)
          local tail=owner.default_owner(source)
          assert(tail.unit.count==675 and tail.unit.count_formula==nil and tail.prerequisites==nil)
          assert(owner.matches_default_owner(native(source),native(tail)))
        ''')

    def test_ordinary_preserves_authored_enablement_and_disabled_visibility_exactly(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.stage(target).execute(r'''
                  for _,enabled in ipairs({"absent",false,true})do
                    for _,visible in ipairs({"absent",false,true})do
                      local source=authored()
                      source.enabled=enabled~="absent" and enabled or nil
                      source.visible_when_disabled=visible~="absent" and visible or nil
                      -- Explicit false must remain distinguishable from omission.
                      if enabled==false then source.enabled=false end
                      if visible==false then source.visible_when_disabled=false end
                      for _,id in ipairs({owner.ordinary_provider_id})do
                        local row=owner.ordinary(source,id)
                        assert(row.hidden==false and row.enabled==source.enabled)
                        assert(row.visible_when_disabled==source.visible_when_disabled)
                      end
                      local tail=owner.default_owner(source)
                      assert(tail.enabled==source.enabled and tail.visible_when_disabled==source.visible_when_disabled)
                    end
                  end
                ''')

    def test_invalid_level_identity_effect_and_unit_refuse_without_mutating_inputs(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.stage(target).execute(r'''
                  for _,change in ipairs({
                    function(s)s.type="recipe"end,function(s)s.name=""end,
                    function(s)s.name="worker-robots-storage-6"end,
                    function(s)s.level=6 end,function(s)s.level=9 end,function(s)s.max_level=4 end,
                    function(s)s.enabled="yes"end,function(s)s.visible_when_disabled=1 end,
                    function(s)s.ignore_tech_cost_multiplier="false"end,
                    function(s)s.name=owner.id end,function(s)s.name=owner.ordinary_default_id end,
                    function(s)s.name=owner.ordinary_provider_id end,function(s)s.name=owner.provider_debit_id end,
                    function(s)s.effects={}end,function(s)s.effects[2]=deep(s.effects[1])end,
                    function(s)s.effects[1].modifier=-1 end,function(s)s.effects[1].modifier=math.huge end,
                    function(s)s.effects[1].type="laboratory-speed"end,
                    function(s)s.unit.time=0 end,function(s)s.unit.time=math.huge end,
                    function(s)s.unit.count=1 end,function(s)s.unit.count_formula=""end,
                    function(s)s.unit.count_formula=nil;s.unit.count=2^64 end,
                    function(s)s.unit.count_formula=nil end,function(s)s.unit.ingredients={}end,
                    function(s)s.unit.ingredients[1][2]=.5 end,
                    function(s)s.unit.ingredients[1][2]=65536 end,
                    function(s)s.prerequisites[2]=s.prerequisites[1]end,
                    function(s)s.prerequisites[1]=s.name end})do
                    local source=authored();change(source);refused(source)
                  end
                  for _,source in ipairs({false,1,"authored"})do
                    assert(not pcall(owner.ordinary,source,owner.ordinary_provider_id))
                    assert(not pcall(owner.debit,source))
                  end
                  assert(not pcall(owner.ordinary,nil,owner.ordinary_provider_id))
                  for _,id in ipairs({owner.id,owner.canonical,owner.ordinary_default_id,owner.provider_debit_id,owner.head_id,"foreign-4"})do
                    assert(not pcall(owner.ordinary,authored(),id))
                  end
                ''')

    def test_first_level_debit_uses_public_scalar_without_scaling_the_default_owner(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.stage(target).execute(r'''
                  local source=authored();local before=deep(source)
                  for _,public_scalar in ipairs({0,2})do
                    assert(owner.default_owner(source).effects[1].modifier==1)
                    assert(owner.head_debit(source,public_scalar).effects[1].modifier==-public_scalar)
                    same(source,before)
                  end
                  for _,invalid in ipairs({-1,math.huge,"2",{}})do
                    assert(not pcall(owner.head_debit,source,invalid));same(source,before)
                  end
                ''')
        _, lua = self.pipeline(rows=worker_pipeline.finite_chain(5))
        lua.execute('''
          assert(data.raw.technology["worker-robots-storage-4"].effects[1].modifier==2)
          assert(data.raw.technology["mir-worker-storage-default-4"].effects[1].modifier==1)
          assert(data.raw.technology["mir-worker-storage-head-4"].effects[1].modifier==-2)
        ''')

    def test_holes_self_prerequisites_and_executable_or_cyclic_data_refuse(self):
        lua = self.stage()
        lua.execute(r'''
          local source=authored();source.prerequisites[1]=owner.ordinary_provider_id
          assert(not pcall(owner.ordinary,source,owner.ordinary_provider_id))
          source=authored();source.prerequisites[1]=owner.provider_debit_id
          assert(not pcall(owner.debit,source))
          source=authored();source.unit.ingredients[2]=nil;refused(source)
          source=authored();source.icons[1].callback=function()end
          assert(not pcall(owner.debit,source))
          source=authored();source.icons[1].cycle=source
          assert(not pcall(owner.ordinary,source,owner.ordinary_provider_id))
          source=authored();setmetatable(source.icons[1],{})
          assert(not pcall(owner.debit,source))
          source=authored();source.icons[1].tint.r=0/0
          assert(not pcall(owner.debit,source))
        ''')

    def test_legacy_prepared_constructors_and_default_matching_keep_their_contract(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                self.stage(target).execute(r'''
                  local source=authored();local expected=deep(source)
                  expected.name="mir-worker-storage-preservation-4"
                  expected.hidden,expected.enabled,expected.visible_when_disabled=true,false,false
                  expected.order="zz[mir-worker-storage-preservation]"
                  same(owner.prototype(source),expected)
                  expected.prerequisites={};expected.unit={count=1,time=1,ingredients={{"automation-science-pack",1}}}
                  same(owner.uninvested(source,"automation-science-pack"),expected)
                  -- The legacy fingerprint deliberately accepts only its old runtime effect shape.
                  source.effects[1].infer_icon=nil
                  assert(owner.matches_default(deep(source),source))
                  local changed=deep(source);changed.unit.time=61
                  assert(not owner.matches_default(changed,source))
                ''')

    def test_split_transport_is_optional_strict_boolean_and_never_saved_authority(self):
        self.stage().execute(r'''
          local bridge=require("research.native_adoption")
          storage=setmetatable({}, {__index=function()error("read saved history")end,
            __newindex=function()error("wrote saved history")end})
          for _,split in ipairs({false,true})do
            local prototype=bridge.prototype();local before=deep(prototype)
            local patch=bridge.plan({["mod-data"]={[prototype.name]=prototype}}, {},nil,nil,nil,split)
            same(prototype,before);bridge.apply(patch)
            assert(prototype.data.worker_default_split==split)
            local facts={}
            assert(select("#",bridge.read(prototype.data,{},facts))==3)
            assert(facts.worker_default_split==split)
          end
          local facts={};bridge.read({schema=1,owners={}}, {},facts)
          assert(facts.worker_default_split==false)
          for _,bad in ipairs({1,"true",{}})do
            assert(not pcall(bridge.read,{schema=1,owners={},worker_default_split=bad},{},{}))
            assert(not pcall(bridge.plan,{}, {},nil,nil,nil,bad))
          end
        ''')

    def test_real_pipeline_preserves_public_default_and_legacy_holder_full_contract(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                _, lua = self.pipeline(target)
                plain = worker_pipeline.scaffold.plain_lua
                rows = lua.globals().data.raw.technology
                self.assertEqual(expected_private_worker_row(), plain(rows["mir-worker-storage-preservation-4"]))
                lua.execute('''
                  local public=data.raw.technology["worker-robots-storage-4"]
                  local tail=data.raw.technology["mir-worker-storage-default-4"]
                  local gate=data.raw.technology["mir-worker-storage-head-4"]
                  assert(public.level==4 and public.max_level=="infinite")
                  assert(public.unit.count_formula=="675*1.5^(L-4)" and public.unit.time==60)
                  assert(#public.effects==1 and public.effects[1].modifier==1)
                  assert(tail.level==4 and tail.max_level=="infinite" and tail.hidden==false)
                  assert(tail.unit.count_formula==public.unit.count_formula and tail.unit.time==public.unit.time)
                  assert(#tail.unit.ingredients==#public.unit.ingredients)
                  assert(#tail.prerequisites==#public.prerequisites)
                  for i,entry in ipairs(public.unit.ingredients)do
                    assert(tail.unit.ingredients[i][1]==entry[1] and tail.unit.ingredients[i][2]==entry[2])
                  end
                  for i,name in ipairs(public.prerequisites)do assert(tail.prerequisites[i]==name)end
                  assert(gate.hidden and gate.enabled==false and gate.max_level==4)
                  assert(gate.unit.count==1 and gate.unit.time==1 and #gate.unit.ingredients==1)
                  assert(gate.unit.ingredients[1][1]==public.unit.ingredients[1][1])
                  assert(gate.effects[1].modifier==-public.effects[1].modifier and next(gate.prerequisites)==nil)
                  assert(data.raw["mod-data"]["more-infinite-research-native-adoptions"].data.worker_default_split==true)
                  assert(data.writes==1)
                ''')

    def test_finite_profile_retains_hidden_default_contract_without_new_free_research(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                originals = worker_pipeline.finite_chain(5)
                _, lua = self.pipeline(target, rows=originals)
                plain = worker_pipeline.scaffold.plain_lua
                for name, row in originals.items():
                    self.assertEqual(row, plain(lua.globals().data.raw.technology[name]))
                self.assertEqual(expected_private_worker_row(), plain(
                    lua.globals().data.raw.technology["mir-worker-storage-preservation-4"]))
                lua.execute('''
                  local tail=data.raw.technology["mir-worker-storage-default-4"]
                  local private=data.raw.technology["mir-worker-storage-preservation-4"]
                  assert(tail.hidden and tail.enabled==false and tail.visible_when_disabled==false)
                  assert(tail.unit.count_formula==private.unit.count_formula and tail.unit.time==private.unit.time)
                  assert(data.raw.technology["worker-robots-storage-6"].hidden~=true)
                  assert(data.writes==1)
                ''')

    def test_unavailable_default_contract_is_not_admitted_as_split(self):
        _, lua = self.pipeline(rows=worker_pipeline.finite_chain(5),
            before='data.raw.technology["worker-robots-storage-2"]=nil')
        expected = expected_private_worker_row("automation-science-pack")
        expected["prerequisites"] = []  # This scaffold serializes empty Lua arrays as lists.
        self.assertEqual(expected, worker_pipeline.scaffold.plain_lua(
            lua.globals().data.raw.technology["mir-worker-storage-preservation-4"]))
        lua.execute('''
          assert(data.raw["mod-data"]["more-infinite-research-native-adoptions"].data.worker_default_split==false)
          assert(data.raw.technology["mir-worker-storage-default-4"]==nil)
          assert(data.raw.technology["mir-worker-storage-head-4"]==nil)
        ''')

    def test_science_policy_applies_to_tail_but_never_bookkeeping_gate(self):
        for target in ("f200", "f210"):
            for sif in (False, True):
                with self.subTest(target=target, sif=sif):
                    extra = {"space-age": worker_pipeline.EDITIONS[target]["minimum_base"]}
                    if sif:
                        extra["space-is-fake"] = "1.0.78"
                    _, lua = self.pipeline(target, extra_mods=extra,
                        changes={"mir-science-pack-ingredient-policy": "all-official"})
                    lua.execute('''
                      local public=data.raw.technology["worker-robots-storage-4"]
                      local tail=data.raw.technology["mir-worker-storage-default-4"]
                      local private=data.raw.technology["mir-worker-storage-preservation-4"]
                      local gate=data.raw.technology["mir-worker-storage-head-4"]
                      assert(#tail.unit.ingredients==#public.unit.ingredients)
                      assert(#tail.unit.ingredients==#private.unit.ingredients)
                      for i,v in ipairs(public.unit.ingredients)do
                        assert(tail.unit.ingredients[i][1]==v[1] and tail.unit.ingredients[i][2]==v[2])
                      end
                      assert(gate.unit.count==1 and gate.unit.time==1 and #gate.unit.ingredients==1)
                      assert(gate.unit.ingredients[1][1]==public.unit.ingredients[1][1])
                      assert(next(gate.prerequisites)==nil)
                    ''')

    def test_runtime_catalogue_declares_only_real_default_head_tail_and_internal_gate(self):
        case, lua = self.pipeline()
        self.runtime_catalogue(case, lua)
        lua.execute('''
          local catalogue=parse_worker_catalogue();assert(catalogue.worker_default_split())
          local found={};for _,row in ipairs(catalogue.declared())do found[row.id]=row end
          local head,tail=found["worker-robots-storage-4"],found["mir-worker-storage-default-4"]
          assert(head.fixed_maximum==4 and tail.progression==4 and tail.fixed_maximum==nil)
          assert(tail.family==head.family and tail.setting==head.setting and tail.cap_setting==head.cap_setting)
          assert(found["mir-worker-storage-head-4"]==nil)
          assert(catalogue.internal_credit_ids()["mir-worker-storage-head-4"]==true)
          assert(catalogue.internal_credit_ids()["mir-worker-storage-default-4"]==nil)
          head.fixed_maximum=99;tail.progression=99
          for _,row in ipairs(catalogue.declared())do
            if row.id=="worker-robots-storage-4"then assert(row.fixed_maximum==4)end
            if row.id=="mir-worker-storage-default-4"then assert(row.progression==4)end
          end
          local pure=require("research.catalogue")
          assert(not pcall(pure.declared,nil,nil,false,nil,"true"))
        ''')
        case, lua = self.pipeline(rows=worker_pipeline.finite_chain(5))
        self.runtime_catalogue(case, lua)
        lua.execute('''
          for _,row in ipairs(parse_worker_catalogue().declared())do
            assert(row.id~="mir-worker-storage-default-4" and row.id~="mir-worker-storage-head-4")
            if row.id=="worker-robots-storage-6"then assert(row.fixed_maximum==nil)end
          end
        ''')

    def test_runtime_split_fact_cannot_admit_missing_or_foreign_identity(self):
        for mode in ("missing", "foreign", "wrong-level", "wrong-bound", "missing-source", "foreign-source"):
            with self.subTest(mode=mode):
                case, lua = self.pipeline()
                self.runtime_catalogue(case, lua)
                lua.globals().mode = mode
                lua.execute('''
                  local id="mir-worker-storage-default-4"
                  if mode=="missing"then native_prototypes[id]=nil
                  elseif mode=="wrong-level"then native_prototypes[id].level=5
                  elseif mode=="wrong-bound"then native_prototypes[id].max_level=5
                  elseif mode=="missing-source"then native_prototypes["worker-robots-storage-4"]=nil
                  else prototypes.get_history=function(kind,name)
                    local foreign=mode=="foreign" and id or "worker-robots-storage-4"
                    return {created=name==foreign and "foreign" or "more-infinite-research"}
                  end end
                  local ok,message=pcall(parse_worker_catalogue)
                  assert(not ok and tostring(message):find("MIR worker default",1,true))
                ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(WorkerNativeOwnerDataTests))
    sys.exit(0 if result.wasSuccessful() else 1)

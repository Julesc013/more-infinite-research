"""Pure native gun holder construction controls; no Factorio/save acceptance."""
import argparse
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]


class NativeGunCreditDefinitionTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute(r'''
          package.path=player_root.."/?.lua;"..player_root.."/?/init.lua"
          package.cpath=""
          local poison=setmetatable({},{__index=function() error("read global input") end,
            __pairs=function() error("scanned global input") end})
          data,raw,game,mods,settings,prototypes=poison,poison,poison,poison,poison,poison
          credit=require("research.native_gun_credit_definitions")
          main="recipe-prod-research_electric_shooting_speed-1"
          ids={
            "mir-native-credit-research_electric_shooting_speed-electric-positive",
            "zz-mir-native-credit-research_electric_shooting_speed-electric-negative",
            "mir-native-credit-research_electric_shooting_speed-tesla-positive",
            "zz-mir-native-credit-research_electric_shooting_speed-tesla-negative",
          }
          function full(electric,tesla)
            return {type="technology",name=main,
              effects={{type="gun-speed",ammo_category="electric",modifier=electric},
                {type="gun-speed",ammo_category="tesla",modifier=tesla}},
              unit={count_formula="60*1.5^(L-1)",time=60,
                ingredients={{"authored-science",7},{"later-science",2}}}}
          end
          function selected(row,mask)
            local effects={}
            for index=1,2 do
              if mask[index] then
                local effect=row.effects[index]
                effects[#effects+1]={type=effect.type,ammo_category=effect.ammo_category,
                  modifier=effect.modifier}
              end
            end
            return {type="technology",name=main,effects=effects}
          end
          function same(a,b)
            if type(a)~=type(b) then return false end
            if type(a)~="table" then return a==b end
            for key,value in pairs(a) do if not same(value,b[key]) then return false end end
            for key in pairs(b) do if a[key]==nil then return false end end
            return true
          end
          function refuse(body)
            local ok,message=pcall(body)
            assert(not ok,"required rejection absent")
            assert(tostring(message):find("MIR native gun credit",1,true),message)
          end
          function expected(name,category,modifier,order)
            return {type="technology",name=name,
              icon="__base__/graphics/technology/automation-1.png",icon_size=256,
              hidden=true,enabled=false,visible_when_disabled=false,upgrade=true,
              level=1,max_level="infinite",order=order,
              effects={{type="gun-speed",ammo_category=category,modifier=modifier}},
              unit={count_formula="1",time=1,ingredients={{"authored-science",1}}}}
          end
        ''')

    def test_literal_descriptors_private_identity_set_and_detachment(self):
        self.lua.execute(r'''
          assert(credit.main_id==main)
          local want={
            {main_id=main,category="electric",positive_id=ids[1],negative_id=ids[2]},
            {main_id=main,category="tesla",positive_id=ids[3],negative_id=ids[4]},
          }
          local rows=credit.descriptors()
          assert(same(rows,want))
          local names=credit.private_ids();local count=0
          for name,value in pairs(names) do assert(value==true);count=count+1 end
          assert(count==4)
          for _,name in ipairs(ids) do assert(names[name]) end
          assert(ids[2]>main and ids[2]>ids[1] and ids[4]>main and ids[4]>ids[3])
          rows[1].category="foreign";rows[2].positive_id="foreign";names[ids[1]]=false
          assert(same(credit.descriptors(),want) and credit.private_ids()[ids[1]])
        ''')

    def test_exact_native_shapes_for_every_mask_with_zero_and_nondefault_scalars(self):
        self.lua.execute(r'''
          local masks={{false,false},{true,true},{true,false},{false,true}}
          for _,scalar in ipairs({0,.17}) do
            for _,mask in ipairs(masks) do
              local source=full(scalar,scalar)
              local rows=credit.technologies(source,selected(source,mask))
              local want={
                expected(ids[1],"electric",scalar,"zz[mir-native-gun-credit]-electric-positive"),
                expected(ids[2],"electric",mask[1] and -scalar or 0,
                  "zzz[mir-native-gun-credit]-electric-negative"),
                expected(ids[3],"tesla",scalar,"zz[mir-native-gun-credit]-tesla-positive"),
                expected(ids[4],"tesla",mask[2] and -scalar or 0,
                  "zzz[mir-native-gun-credit]-tesla-negative"),
              }
              assert(same(rows,want),"holder shape/scalar/mask differs")
              assert(source.effects[1].modifier==scalar and source.unit.ingredients[1][2]==7)
            end
          end
        ''')

    def test_full_category_scalar_correspondence_and_effect_permutations(self):
        self.lua.execute(r'''
          local source=full(.17,.31)
          local public=selected(source,{false,true})
          local rows=credit.technologies(source,public)
          assert(rows[1].effects[1].modifier==.17 and rows[2].effects[1].modifier==0)
          assert(rows[3].effects[1].modifier==.31 and rows[4].effects[1].modifier==-.31)
          source.effects[1],source.effects[2]=source.effects[2],source.effects[1]
          assert(same(rows,credit.technologies(source,public)))
          public=selected(source,{true,true})
          local original=credit.technologies(source,public)
          public.effects[1],public.effects[2]=public.effects[2],public.effects[1]
          assert(same(original,credit.technologies(source,public)))
          -- A selected literal zero still means the category is present.
          source=full(0,.17);public=selected(source,{true,true})
          assert(credit.technologies(source,public)[4].effects[1].modifier==-.17)
        ''')

    def test_every_nested_output_table_is_detached_from_inputs_and_other_results(self):
        self.lua.execute(r'''
          local source=full(.17,.31);local public=selected(source,{true,false})
          -- Sharing consumed input effects is harmless: outputs own all their tables.
          public.effects[1]=source.effects[1]
          local a=credit.technologies(source,public)
          local b=credit.technologies(source,public)
          local seen={}
          local function visit(value)
            if type(value)~="table" then return end
            assert(not seen[value],"nested table alias")
            seen[value]=true
            for _,child in pairs(value) do visit(child) end
          end
          visit(source);visit(a);visit(b)
          a[1].effects[1].modifier=99;a[1].unit.ingredients[1][1]="foreign"
          assert(a[2].effects[1].modifier==-.17 and a[2].unit.ingredients[1][1]=="authored-science")
          assert(b[1].effects[1].modifier==.17 and b[1].unit.ingredients[1][1]=="authored-science")
          assert(source.effects[1].modifier==.17 and public.effects[1].modifier==.17)
          source.effects[2].modifier=.99;source.unit.ingredients[1][1]="later"
          assert(b[3].effects[1].modifier==.31 and b[3].unit.ingredients[1][1]=="authored-science")
        ''')

    def test_malformed_full_rows_effects_categories_and_scalars_refuse(self):
        self.lua.execute(r'''
          local cases={
            function(r) return false end,
            function(r) return setmetatable(r,{}) end,
            function(r) r.type="item";return r end,
            function(r) r.name="foreign";return r end,
            function(r) r.effects=nil;return r end,
            function(r) r.effects={};return r end,
            function(r) r.effects={r.effects[2]};return r end,
            function(r) r.effects[3]=r.effects[2];return r end,
            function(r) r.effects[1]=nil;return r end,
            function(r) r.effects.foreign=true;return r end,
            function(r) r.effects=setmetatable(r.effects,{});return r end,
            function(r) r.effects[2]=false;return r end,
            function(r) r.effects[2]=setmetatable(r.effects[2],{});return r end,
            function(r) r.effects[2].type="ammo-damage";return r end,
            function(r) r.effects[2].ammo_category="cannon-shell";return r end,
            function(r) r.effects[2].ammo_category="electric";return r end,
            function(r) r.effects[2].unknown=true;return r end,
          }
          for _,change in ipairs(cases) do
            local r=change(full(.17,.31))
            refuse(function() credit.technologies(r,{type="technology",name=main,effects={}}) end)
          end
          for _,value in ipairs({false,".17",-.01,math.huge,-math.huge,0/0}) do
            local r=full(.17,.31);r.effects[2].modifier=value
            refuse(function() credit.technologies(r,selected(full(.17,.31),{})) end)
          end
          local r=full(.17,.31);r.effects[2].modifier=nil
          refuse(function() credit.technologies(r,selected(full(.17,.31),{})) end)
        ''')

    def test_selected_public_identity_and_exact_effect_subset_are_required(self):
        self.lua.execute(r'''
          local source=full(.17,.31)
          refuse(function() credit.technologies(source,nil) end)
          local cases={
            function(r) return false end,
            function(r) r.type="item";return r end,
            function(r) r.name="foreign";return r end,
            function(r) r.effects=nil;return r end,
            function(r) r.effects[2].modifier=.17;return r end,
            function(r) r.effects[2].modifier=0;return r end,
            function(r) r.effects[2].modifier=nil;return r end,
            function(r) r.effects[2].modifier=0/0;return r end,
            function(r) r.effects[2].ammo_category="foreign";return r end,
            function(r) r.effects[2].ammo_category="electric";return r end,
            function(r) r.effects[2].type="ammo-damage";return r end,
            function(r) r.effects[1]=nil;return r end,
            function(r) r.effects[3]=r.effects[2];return r end,
          }
          for _,change in ipairs(cases) do
            local public=change(selected(source,{true,true}))
            refuse(function() credit.technologies(source,public) end)
            assert(source.effects[1].modifier==.17 and source.effects[2].modifier==.31)
          end
        ''')

    def test_first_authored_science_is_required_without_default_or_search(self):
        self.lua.execute(r'''
          local cases={
            function(r) r.unit=nil end,
            function(r) r.unit.ingredients=nil end,
            function(r) r.unit.ingredients={} end,
            function(r) r.unit.ingredients[1]=nil end,
            function(r) r.unit.ingredients[1]=false end,
            function(r) r.unit.ingredients[1]={name="named-science",amount=7} end,
            function(r) r.unit.ingredients[1][1]="" end,
            function(r) r.unit.ingredients[1][1]="bad\0science" end,
            function(r) r.unit.ingredients[1][1]=false end,
            function(r) r.unit.ingredients[1][2]=nil end,
            function(r) r.unit.ingredients[1][2]=0 end,
            function(r) r.unit.ingredients[1][2]=-.1 end,
            function(r) r.unit.ingredients[1][2]=math.huge end,
            function(r) r.unit.ingredients[1][2]=0/0 end,
            function(r) r.unit.ingredients[1][2]="7" end,
            function(r) r.unit.ingredients[1]=setmetatable(r.unit.ingredients[1],{}) end,
          }
          for _,change in ipairs(cases) do
            local source=full(.17,.31);local public=selected(source,{})
            change(source)
            refuse(function() credit.technologies(source,public) end)
          end
          local source=full(.17,.31);source.unit.ingredients[1]={"different-science",.5}
          local rows=credit.technologies(source,selected(source,{}))
          for _,row in ipairs(rows) do assert(same(row.unit.ingredients,{{"different-science",1}})) end
        ''')

    def test_absence_and_valid_base_only_stream_construct_no_holders(self):
        self.lua.execute(r'''
          local poison=setmetatable({},{__index=function() error("absence consumed input") end})
          assert(same(credit.technologies(),{}))
          assert(same(credit.technologies(nil,poison),{}))
          for _,scalar in ipairs({0,.17}) do
            local base=full(scalar,.31);base.effects[2]=nil
            assert(same(credit.technologies(base,selected(base,{true,false})),{}))
            assert(same(credit.technologies(base,nil),{}))
          end
          local r=full(.17,.31)
          -- Unconsumed row metadata does not cause unrelated traversal/copying.
          r.foreign=poison;r.unit.foreign=poison
          assert(#credit.technologies(r,selected(r,{}))==4)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(NativeGunCreditDefinitionTests))
    raise SystemExit(0 if result.wasSuccessful() else 1)

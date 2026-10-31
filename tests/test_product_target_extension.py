"""Pure controls for bounded product-target extension of MIR-generated technologies."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLAYER = ROOT / "source"


class ProductTargetExtensionTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = PLAYER.as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          extension = require("research.product_target_extension")

          function product(kind, name, fields)
            local row = {type = kind, name = name, amount = 1}
            for key, value in pairs(fields or {}) do row[key] = value end
            return row
          end

          function recipe(ingredients, results, fields)
            local row = {ingredients = ingredients or {}, results = results or {}}
            for key, value in pairs(fields or {}) do row[key] = value end
            return row
          end

          function productivity(recipe_name, change, extra)
            local row = {type = "change-recipe-productivity", recipe = recipe_name, change = change}
            for key, value in pairs(extra or {}) do row[key] = value end
            return row
          end

          function generated(family, effects, enabled)
            local row = {
              name = "recipe-prod-" .. family .. "-1",
              effects = effects,
              order = "p[" .. family .. "]",
              enabled = enabled,
            }
            if enabled == nil then row.enabled = true end
            return row
          end

          function effect_rows(effects)
            local rows = {}
            for _, effect in ipairs(effects) do
              rows[#rows + 1] = effect.type .. ":" .. effect.recipe .. ":" .. string.format("%.5f", effect.change)
            end
            return table.concat(rows, ",")
          end

          function raw_with_recipes(recipes)
            return {
              recipe = recipes,
              technology = setmetatable({}, {
                __index = function(_, key)
                  error("product target extension must not read raw technology " .. tostring(key))
                end,
                __pairs = function()
                  error("product target extension must not scan raw technologies")
                end,
              }),
            }
          end

          function values(gear_effect, furnace_effect, space_effect)
            return {
              effect_percent = gear_effect,
              streams = {
                research_furnace = {effect_percent = furnace_effect},
                research_bioflux = {effect_percent = space_effect},
              },
            }
          end

          function frozen_copy(value, seen)
            if type(value) ~= "table" then return tostring(value) end
            seen = seen or {}
            if seen[value] then return "cycle" end
            seen[value] = true
            local keys = {}
            for key in pairs(value) do keys[#keys + 1] = key end
            table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
            local rows = {}
            for _, key in ipairs(keys) do
              rows[#rows + 1] = tostring(key) .. "=" .. frozen_copy(value[key], seen)
            end
            seen[value] = nil
            return table.concat(rows, "|")
          end

          function assert_result_shape(result)
            assert(type(result) == "table")
            assert(type(result.extended_effects) == "number" and type(result.families) == "number")
            assert(type(result.work) == "table")
          end
        ''')

    def test_base_and_active_space_age_literal_routes_extend_only_existing_generated_rows(self):
        self.lua.execute(r'''
          local gear = generated("research_gears", {productivity("iron-gear-wheel", .10)}, false)
          local bioflux = generated("research_bioflux", {productivity("bioflux", .10)})
          local foreign = {name = "foreign-productivity", order = "foreign", effects = {productivity("foreign", .33)}}
          local technologies = {gear, bioflux, foreign}
          local recipes = {
            ["modded-gear-producer"] = recipe({{"iron-plate", 2}}, {product("item", "iron-gear-wheel")}),
            ["modded-bioflux-producer"] = recipe({}, {product("item", "bioflux")}),
          }
          local base = extension.extend(technologies, values(17, 20, 11), {
            raw = raw_with_recipes(recipes), mods = {}
          })
          assert_result_shape(base)
          assert(base.extended_effects == 1 and base.families == 1)
          assert(base.work.recipes == 2 and base.work.products == 2 and base.work.matches == 1)
          assert(#technologies == 3 and gear.enabled == false and foreign.order == "foreign")
          assert(effect_rows(gear.effects) ==
            "change-recipe-productivity:iron-gear-wheel:0.10000,change-recipe-productivity:modded-gear-producer:0.17000")
          assert(effect_rows(bioflux.effects) == "change-recipe-productivity:bioflux:0.10000")
          assert(effect_rows(foreign.effects) == "change-recipe-productivity:foreign:0.33000")

          local active = extension.extend(technologies, values(17, 20, 11), {
            raw = raw_with_recipes(recipes), mods = {['space-age'] = '2.1.23'}
          })
          assert_result_shape(active)
          assert(active.extended_effects == 1 and active.families == 1)
          assert(active.work.recipes == 2 and active.work.products == 2 and active.work.matches == 2)
          assert(effect_rows(gear.effects) ==
            "change-recipe-productivity:iron-gear-wheel:0.10000,change-recipe-productivity:modded-gear-producer:0.17000")
          assert(effect_rows(bioflux.effects) ==
            "change-recipe-productivity:bioflux:0.10000,change-recipe-productivity:modded-bioflux-producer:0.11000")
          assert(effect_rows(foreign.effects) == "change-recipe-productivity:foreign:0.33000")
        ''')

    def test_weighted_furnace_routes_scale_current_stream_setting_and_append_in_recipe_order(self):
        self.lua.execute(r'''
          local original = productivity("stone-furnace", .20, {note = "preserve"})
          local furnace = generated("research_furnace", {original})
          local technologies = {furnace}
          local recipes = {
            ["a-stone-furnace"] = recipe({}, {product("item", "stone-furnace")}),
            ["b-steel-furnace"] = recipe({}, {product("item", "steel-furnace")}),
            ["c-electric-furnace"] = recipe({}, {product("item", "electric-furnace")}),
          }
          local bindings = require("compatibility.product_bindings")
          local recipes_before, bindings_before = frozen_copy(recipes), frozen_copy(bindings)
          local result = extension.extend(technologies, values(10, 20, 10), {
            raw = raw_with_recipes(recipes),
            mods = {},
          })
          assert_result_shape(result)
          assert(result.extended_effects == 3 and result.families == 1)
          assert(result.work.recipes == 3 and result.work.products == 3 and result.work.matches == 3)
          assert(original.note == "preserve" and furnace.effects[1] == original)
          assert(frozen_copy(recipes) == recipes_before and frozen_copy(bindings) == bindings_before)
          assert(effect_rows(furnace.effects) ==
            "change-recipe-productivity:stone-furnace:0.20000,"
            .. "change-recipe-productivity:a-stone-furnace:0.20000,"
            .. "change-recipe-productivity:b-steel-furnace:0.10000,"
            .. "change-recipe-productivity:c-electric-furnace:0.05000")
        ''')

    def test_exclusions_typed_homonyms_and_unsupported_literal_routes_do_not_widen_productivity(self):
        self.lua.execute(r'''
          local gear = generated("research_gears", {productivity("iron-gear-wheel", .10)})
          local explosives = generated("research_explosives", {productivity("explosives", .10)})
          local technologies = {gear, explosives}
          local result = extension.extend(technologies, values(10, 20, 10), {
            raw = raw_with_recipes({
              valid = recipe({{"iron-plate", 2}}, {product("item", "iron-gear-wheel")}),
              scrap = recipe({{"scrap", 1}}, {product("item", "iron-gear-wheel")}),
              recycling = recipe({{"iron-plate", 2}}, {product("item", "iron-gear-wheel")}, {category = "recycling"}),
              returned = recipe({{"iron-gear-wheel", 1}}, {product("item", "iron-gear-wheel", {catalyst_amount = 1})}),
              ignored = recipe({}, {product("item", "iron-gear-wheel", {ignored_by_productivity = 1})}),
              fluid_homonym = recipe({}, {product("fluid", "iron-gear-wheel")}),
              malformed = {ingredients = {}, results = "not-an-array"},
              bio_explosives = recipe({}, {product("item", "bio-explosives")}),
            }),
            mods = {},
          })
          assert_result_shape(result)
          assert(result.extended_effects == 1 and result.families == 1)
          assert(result.work.recipes == 8 and result.work.products == 7 and result.work.matches == 4)
          assert(effect_rows(gear.effects) ==
            "change-recipe-productivity:iron-gear-wheel:0.10000,change-recipe-productivity:valid:0.10000")
          assert(effect_rows(explosives.effects) == "change-recipe-productivity:explosives:0.10000")
        ''')

    def test_extension_uses_one_recipe_product_pass_across_families_and_never_touches_raw_or_foreign_rows(self):
        self.lua.execute(r'''
          local gear = generated("research_gears", {productivity("iron-gear-wheel", .10)})
          local furnace = generated("research_furnace", {productivity("stone-furnace", .20)})
          local foreign = {name = "foreign", effects = {productivity("foreign", .50)}}
          local recipes = {
            gear_route = recipe({}, {product("item", "iron-gear-wheel")}),
            furnace_route = recipe({}, {product("item", "stone-furnace")}),
          }
          for index = 1, 100 do
            recipes["unrelated-" .. index] = recipe({}, {product("item", "other-" .. index)})
          end
          local recipe_passes = 0
          setmetatable(recipes, {
            __pairs = function(value)
              recipe_passes = recipe_passes + 1
              return next, value, nil
            end,
          })
          local result = extension.extend({gear, furnace, foreign}, values(10, 20, 10), {
            raw = raw_with_recipes(recipes), mods = {},
          })
          assert_result_shape(result)
          assert(result.extended_effects == 2 and result.families == 2)
          assert(recipe_passes == 1)
          assert(result.work.recipes == 102 and result.work.products == 102 and result.work.matches == 2)
          assert(effect_rows(foreign.effects) == "change-recipe-productivity:foreign:0.50000")
        ''')

    def test_no_eligible_generated_family_does_not_enumerate_recipes(self):
        self.lua.execute(r'''
          local attempted = false
          local recipes = setmetatable({}, {
            __pairs = function()
              attempted = true
              error("no eligible family must skip collection")
            end,
          })
          package.loaded["compatibility.product_bindings"] = nil
          package.loaded["compatibility.product_targets"] = nil
          package.preload["compatibility.product_bindings"] = function()
            error("no eligible family must not import bindings")
          end
          package.preload["compatibility.product_targets"] = function()
            error("no eligible family must not import collector")
          end
          local foreign = {name = "foreign-productivity", effects = {productivity("foreign", .5)}}
          local result = extension.extend({foreign}, values(10, 20, 10), {
            raw = raw_with_recipes(recipes), mods = {['space-age'] = '2.1.23'},
          })
          assert_result_shape(result)
          assert(result.extended_effects == 0 and result.families == 0)
          assert(not attempted and effect_rows(foreign.effects) == "change-recipe-productivity:foreign:0.50000")
          assert(result.work.recipes == 0 and result.work.products == 0 and result.work.matches == 0)
        ''')


    def test_native_module_tiers_extend_all_producers_in_one_shared_recipe_pass(self):
        self.lua.execute(r'''
          local row = generated("research_modules", {productivity("known-module", .33)})
          local recipes = {}
          local modules = {}
          for tier=1,5 do
            local name="custom-module-" .. tier
            modules[name]={tier=tier,foreign="preserve"}
            recipes["producer-" .. tier]=recipe({}, {product("item",name)})
          end
          modules.zero={tier=0}; modules.invalid={tier="2"}
          recipes.ignored=recipe({}, {product("item","custom-module-5",{ignored_by_productivity=1})})
          recipes.homonym=recipe({}, {product("fluid","custom-module-1")})
          local raw=raw_with_recipes(recipes); raw.module=modules
          local before=frozen_copy(raw.module)
          local result=extension.extend({row}, {streams={research_modules={effect_percent=20}}}, {raw=raw,mods={}})
          assert(effect_rows(row.effects) == "change-recipe-productivity:known-module:0.33000,"
            .. "change-recipe-productivity:producer-1:0.20000,"
            .. "change-recipe-productivity:producer-2:0.10000,"
            .. "change-recipe-productivity:producer-3:0.04000,"
            .. "change-recipe-productivity:producer-4:0.02000,"
            .. "change-recipe-productivity:producer-5:0.02000")
          assert(result.extended_effects == 5 and result.families == 1)
          assert(result.work.recipes == 7 and result.work.products == 7 and result.work.modules == 7)
          assert(frozen_copy(raw.module) == before)
        ''')

    def test_module_class_is_lazy_and_insertion_order_does_not_change_tier_priority(self):
        self.lua.execute(r'''
          local raw=raw_with_recipes({})
          raw.module=setmetatable({}, {__pairs=function() error("unselected module class traversal") end})
          extension.extend({generated("research_gears", {productivity("known",.1)})},
            values(10,20,10), {raw=raw,mods={}})
          local function output(reverse)
            local module={}
            if reverse then module.higher={tier=4}; module.lower={tier=1}
            else module.lower={tier=1}; module.higher={tier=4} end
            local source=raw_with_recipes({mixed=recipe({}, {product("item","higher"),product("item","lower")})})
            source.module=module
            local row=generated("research_modules", {productivity("known",.1)})
            extension.extend({row}, {streams={research_modules={effect_percent=10}}}, {raw=source,mods={}})
            return effect_rows(row.effects)
          end
          assert(output(false)==output(true))
          assert(output(false)=="change-recipe-productivity:known:0.10000,change-recipe-productivity:mixed:0.10000")
        ''')


    def test_published_pattern_groups_preserve_weights_settings_and_explicit_routes(self):
        self.lua.execute(r'''
          local cases={
            {'research_explosives',10,'bio-explosives',.1,'item'},
            {'research_mining_drill',40,'kr-quarry-drill',.1,'item'},
            {'research_bullets',10,'tungsten-rifle-magazine',.01,'ammo'},
            {'research_heavy_ammo',10,'kr-antimatter-artillery-shell',.01,'ammo'},
            {'research_rockets',10,'plutonium-heavy-bomb',.01,'ammo'},
            {'research_belts',10,'kr-fast-loader',.05,'item'},
            {'research_belts',10,'kr-express-loader',.02,'item'},
            {'research_belts',10,'custom-hyper-loader',.005,'item'},
            {'research_inserters',10,'custom-bulk-inserter',.02,'item'},
            {'research_inserters',10,'custom-stack-inserter',.01,'item'},
            {'research_armor_components',10,'titanium-armour-plating',.05,'item'},
            {'research_armor_components',10,'armor-plate-heavy',.02,'item'},
            {'research_artificial_soil',10,'artificial-new-soil',.1,'item'},
            {'research_artificial_soil',10,'overgrowth-new-soil',.05,'item'},
          }
          for _,case in ipairs(cases) do
            local family,percent,name,expected,kind=table.unpack(case)
            local row=generated(family, {productivity('known',.33)})
            local raw=raw_with_recipes({producer=recipe({}, {product('item',name)}),
              fluid=recipe({}, {product('fluid',name)}),
              hidden=recipe({}, {product('item',name)}, {hidden=true})})
            raw[kind]={[name]={}}
            local result=extension.extend({row}, {streams={[family]={effect_percent=percent}}}, {
              raw=raw, mods={['space-age']='2.1.23'}})
            assert(result.extended_effects == 1 and #row.effects == 2, family .. ':' .. name)
            assert(row.effects[1].change == .33 and row.effects[2].recipe == 'producer')
            assert(math.abs(row.effects[2].change-expected) < 1e-12, family .. ':' .. name)
            assert(result.work.items == 1 and result.work.recipes == 3)
          end
        ''')

    def test_exact_recipe_and_breeding_batch_keeps_published_or_semantics_and_weights(self):
        self.lua.execute(r'''
          local cases={
            {'research_oil_processing_productivity','advanced-oil-processing',1,'oil',true},
            {'research_oil_cracking_productivity','heavy-oil-cracking',1,'light-oil'},
            {'research_sulfuric_acid_productivity','acid-neutralisation',1,'stone'},
            {'research_sulfuric_acid_productivity','acid-neutralization',1,'stone'},
            {'research_carbon','carbonic-asteroid-crushing',1,'unrelated-output'},
            {'research_carbon','burnt-spoilage',.5,'carbon'},
            {'research_carbon','coal-synthesis',.2,'coal'},
            {'research_ice','oxide-asteroid-crushing',1,'unrelated-output'},
            {'research_bacteria_cultivation','iron-bacteria-cultivation',1,'bacteria',true},
            {'research_nutrients','nutrients-from-bioflux',1,'nutrients'},
            {'research_capture_robot_rockets','capture-robot-rocket',1,'rocket'},
            {'research_molten_metals','molten-iron-from-lava',1,'molten-iron'},
            {'research_molten_metals','iron-ore-melting',.5,'molten-iron'},
            {'research_lithium','lithium',.5,'lithium'},
            {'research_breeding','custom-culture',1,'custom-egg',true},
          }
          for _,case in ipairs(cases) do
            local family,name,weight,output,shared=table.unpack(case)
            local row=generated(family, {productivity('known',.33)})
            local raw=raw_with_recipes({[name]=recipe(shared and {{output,1}} or {},
              {product('item',output,{amount=2})})})
            if family == 'research_carbon' or family == 'research_ice' then raw.technology={} end
            local result=extension.extend({row}, {streams={[family]={effect_percent=20}}}, {
              raw=raw,mods={['space-age']='2.1.23'}})
            assert(result.extended_effects == 1 and #row.effects == 2, family .. ':' .. name)
            assert(row.effects[2].recipe == name and math.abs(row.effects[2].change-.2*weight)<1e-12)
          end
          -- Product alternatives are deliberately ORed with recipe names in
          -- the published selector, including recipes without those names.
          local row=generated('research_breeding', {productivity('known',.33)})
          local result=extension.extend({row}, {streams={research_breeding={effect_percent=10}}}, {
            raw=raw_with_recipes({fish=recipe({}, {product('item','raw-fish')}),
              ['fish-incineration']=recipe({}, {product('item','raw-fish')}),
              ['iron-bacteria-cultivation']=recipe({}, {product('item','biter-egg')})}),mods={}})
          assert(result.extended_effects == 1 and row.effects[2].recipe == 'fish')
        ''')

    def test_carbon_recipe_name_does_not_admit_a_repurposed_angel_product(self):
        self.lua.execute(r'''
          local function run(carbon_recipe)
            local carbon=generated('research_carbon', {
              productivity('burnt-spoilage',.05),productivity('coal-synthesis',.02)})
            local raw=raw_with_recipes({
              carbon=carbon_recipe,
              ['burnt-spoilage']=recipe({}, {product('item','carbon')}),
              ['coal-synthesis']=recipe({}, {product('item','coal')})})
            raw.technology={}
            local before=frozen_copy(raw)
            local result=extension.extend({carbon}, {streams={research_carbon={effect_percent=10}}}, {
              raw=raw,mods={['space-age']='2.1.23'}})
            assert(frozen_copy(raw)==before)
            return effect_rows(carbon.effects),result
          end
          -- Independent q010 upstream/B6 oracle: Angel's hidden carbon recipe
          -- makes angels-solid-carbon, while B6 keeps only these two effects.
          local expected='change-recipe-productivity:burnt-spoilage:0.05000,' ..
            'change-recipe-productivity:coal-synthesis:0.02000'
          local actual,result=run(recipe({}, {product('item','angels-solid-carbon',{amount=2})},
            {hidden=true,enabled=false,allow_productivity=false,allow_decomposition=false}))
          assert(actual==expected,actual)
          assert(result.extended_effects==0)
          assert(run(recipe({}, {product('item','angels-solid-carbon',{amount=2})}))==expected)
          -- A genuine positive item-carbon producer still joins the family;
          -- a fluid homonym or zero-yield result never does.
          actual=run(recipe({}, {product('item','carbon')}, {enabled=false}))
          assert(actual==expected..',change-recipe-productivity:carbon:0.10000',actual)
          assert(run(recipe({}, {product('fluid','carbon')}))==expected)
          assert(run(recipe({}, {product('item','carbon',{amount=0})}))==expected)
        ''')

    def test_native_asteroid_and_scrap_owners_prevent_only_new_duplicate_targets(self):
        self.lua.execute(r'''
          local carbon=generated('research_carbon',{productivity('known',.33)})
          local ice=generated('research_ice',{productivity('earned-mir-target',.44)})
          local raw=raw_with_recipes({
            ['carbonic-asteroid-crushing']=recipe({}, {product('item','carbon')}),
            ['oxide-asteroid-crushing']=recipe({}, {product('item','ice')}),
            ['scrap-recycling']=recipe({}, {product('item','ice')}),
            ['earned-mir-target']=recipe({}, {product('item','ice')}),
            custom=recipe({}, {product('item','ice')})})
          local native={
            ['asteroid-productivity']={effects={productivity('carbonic-asteroid-crushing',.1),
              productivity('oxide-asteroid-crushing',.1)}},
            ['scrap-recycling-productivity']={effects={productivity('scrap-recycling',.1),
              productivity('earned-mir-target',.1)}}}
          local reads=0
          raw.technology=setmetatable({}, {__index=function(_,name)
            reads=reads+1; assert(native[name]); return native[name] end,
            __pairs=function() error('must not inspect unfamiliar foreign research') end})
          local before=frozen_copy(native)
          local result=extension.extend({carbon,ice}, {streams={research_carbon={effect_percent=10},
            research_ice={effect_percent=10}}}, {raw=raw,mods={['space-age']='2.1.23'}})
          assert(result.extended_effects==1 and result.work.owners==2 and reads==2)
          assert(#carbon.effects==1 and #ice.effects==2 and ice.effects[1].change==.44)
          assert(ice.effects[2].recipe=='custom' and frozen_copy(native)==before)
        ''')

    def test_structural_belt_and_inserter_fallbacks_preserve_denials_and_action_settings(self):
        self.lua.execute(r'''
          local function run(action,legacy,create,reviewed)
            local belt=generated('research_belts',{productivity('known',.33)})
            local inserter=generated('research_inserters',{productivity('known',.33)})
            local raw=raw_with_recipes({custom=recipe({}, {product('item','custom-belt')}),
              fast=recipe({}, {product('item','mod-fast-loader')}),
              inserter=recipe({}, {product('item','custom-arm')}),
              denied=recipe({}, {product('item','custom-belt')},{allow_productivity=false})})
            raw.item={['custom-belt']={place_result='unusual-belt'},
              ['custom-arm']={place_result='unusual-arm'},['mod-fast-loader']={place_result='unusual-loader'}}
            local active=(action==nil or action=='apply') and
              (create==true or reviewed==false or (legacy~='off' and legacy~='report'))
            if active then
              raw['transport-belt']={['unusual-belt']={}}
              raw.inserter={['unusual-arm']={}}
              raw.loader={['unusual-loader']={}}
            else
              setmetatable(raw,{__index=function(_,kind)
                if kind=='transport-belt' or kind=='inserter' or kind=='loader' then
                  error('inactive structural fallback inspected entities') end
              end})
            end
            local result=extension.extend({belt,inserter},{streams={research_belts={effect_percent=20},
              research_inserters={effect_percent=20}},options={
                ['mir-automatic-productivity-action']=action,['mir-automatic-compiler-mode']=legacy,
                ['mir-automatic-create-research']=create,['mir-automatic-require-reviewed-data']=reviewed}},
              {raw=raw,mods={}})
            assert(result.extended_effects==(active and 3 or 1))
            assert(result.work.entities==(active and 3 or 0))
            assert(belt.effects[#belt.effects].recipe=='fast' and belt.effects[#belt.effects].change==.1)
            if active then assert(belt.effects[2].change==.01 and inserter.effects[2].change==.02) end
          end
          run(); run('apply'); run('preview'); run('disabled')
          run('apply','off'); run('apply','report')
          run('apply','safe-attach'); run('apply','exact-pack'); run('apply','safe-generate')
          run('apply','off',true); run('apply','report',false,false)
        ''')

    def test_science_productivity_keeps_dynamic_lab_inputs_in_one_recipe_pass(self):
        self.lua.execute(r'''
          local function run(action, reverse)
            local row=generated('research_science_pack_productivity',{productivity('official-producer',.33)})
            local recipes={
              ['official-producer']=recipe({}, {product('item','automation-science-pack')}),
              ['circular-producer']=recipe({}, {product('item','foreign-pack')},{enabled=false}),
              ['seeded-producer']=recipe({}, {product('item','foreign-pack')},{enabled=false}),
              ['ammo-producer']=recipe({}, {product('item','ammo-pack')}),
              fluid=recipe({}, {product('fluid','foreign-pack')}),
              unused=recipe({}, {product('item','unused-item')}),
              denied=recipe({}, {product('item','foreign-pack')},{allow_productivity=false}),
              hidden=recipe({}, {product('item','foreign-pack')},{hidden=true}),
              recycling=recipe({}, {product('item','foreign-pack')},{category='recycling'}),
              zero=recipe({}, {product('item','foreign-pack',{amount=0})}),
            }
            local recipe_count=0
            for _ in pairs(recipes) do recipe_count=recipe_count+1 end
            local recipe_passes,lab_passes=0,0
            setmetatable(recipes,{__pairs=function(value)
              recipe_passes=recipe_passes+1;return next,value,nil end})
            local raw=raw_with_recipes(recipes)
            raw.tool={['foreign-pack']={},['automation-science-pack']={}}
            raw.ammo={['ammo-pack']={}}
            raw.item={['unused-item']={}}
            raw.fluid={['fluid-only']={}}
            local labs={
              alpha={inputs={'foreign-pack','ammo-pack','automation-science-pack','missing'}},
              beta={inputs={'foreign-pack','fluid-only',{name='malformed'}}},
            }
            local order=reverse and {'beta','alpha'} or {'alpha','beta'}
            setmetatable(labs,{__pairs=function(value)
              lab_passes=lab_passes+1
              local index=0
              return function() index=index+1;local key=order[index]
                if key then return key,value[key] end end,value,nil
            end})
            raw.lab=labs
            local result=extension.extend({row}, {
              streams={research_science_pack_productivity={effect_percent=10}},
              options={['mir-automatic-productivity-action']=action},
            },{raw=raw,mods={['space-age']='2.1.23'}})
            assert(result.extended_effects==3 and #row.effects==4,
              'science productivity lost real lab-input item producers or admitted an excluded recipe')
            assert(effect_rows(row.effects)==
              'change-recipe-productivity:official-producer:0.33000,'..
              'change-recipe-productivity:ammo-producer:0.10000,'..
              'change-recipe-productivity:circular-producer:0.10000,'..
              'change-recipe-productivity:seeded-producer:0.10000')
            assert(recipe_passes==1 and result.work.recipes==recipe_count,
              'dynamic science started another recipe pass')
            assert(lab_passes==1 and result.work.labs==2 and result.work.lab_inputs==7,
              'lab-input collection repeated or omitted visited work')
            assert(labs.alpha.inputs[1]=='foreign-pack' and labs.alpha.inputs[2]=='ammo-pack'
              and labs.beta.inputs[1]=='foreign-pack','lab inputs were mutated')
            return effect_rows(row.effects)
          end
          for _,action in ipairs({'apply','preview','disabled'}) do
            assert(run(action,false)==run(action,true),'lab insertion order changed output')
          end
        ''')

    def test_dynamic_science_inputs_respect_selection_exact_bindings_and_empty_inputs(self):
        self.lua.execute(r'''
          local function guarded_raw()
            return setmetatable(raw_with_recipes({known=recipe({}, {product('item','iron-gear-wheel')})}),{
              __index=function(_,key) if key=='lab' then error('inactive science inspected labs') end end})
          end
          local gear=generated('research_gears',{productivity('known',.2)})
          local result=extension.extend({gear},{effect_percent=20},{raw=guarded_raw(),mods={}})
          assert(result.work.labs==0 and result.work.lab_inputs==0)
          local science=generated('research_science_pack_productivity',{productivity('known',.1)})
          result=extension.extend({science},{streams={research_science_pack_productivity={effect_percent=10}}},{
            raw=guarded_raw(),mods={},exact_product_target_families={research_science_pack_productivity=true},
            exact_product_bindings={{family='research_science_pack_productivity',weight=1,recipes={'known'}}}})
          assert(#science.effects==1 and result.work.labs==0 and result.work.lab_inputs==0)
          local raw=raw_with_recipes(setmetatable({},{__pairs=function() error('empty lab rule scanned recipes') end}))
          raw.lab={one={inputs={'absent','fluid-only','bad-item'}}}
          raw.fluid={['fluid-only']={}};raw.item={['bad-item']='not-a-prototype'}
          result=extension.extend({science},{streams={research_science_pack_productivity={effect_percent=10}}},
            {raw=raw,mods={}})
          assert(result.rules==0 and result.work.recipes==0 and result.work.labs==1 and result.work.lab_inputs==3,
            'empty/invalid lab inputs manufactured a rule or lost work counts')
        ''')

    def test_k2_science_card_binding_requires_selected_family_and_complete_markers(self):
        self.lua.execute(r'''
          local function run(mods)
            local row=generated('research_science_pack_productivity',{productivity('known',.33)})
            local result=extension.extend({row}, {streams={research_science_pack_productivity={effect_percent=15}}}, {
              raw=raw_with_recipes({producer=recipe({}, {product('item','kr-advanced-tech-card')}),
                cooling=recipe({}, {product('item','kr-matter-tech-card')}),
                denied=recipe({}, {product('item','kr-singularity-tech-card')},{allow_productivity=false}),
                homonym=recipe({}, {product('fluid','kr-advanced-tech-card')})}),mods=mods})
            return row,result
          end
          package.preload['compatibility.modern_catalogue.k2so']=function() error('inactive K2SO imported') end
          local row,result=run({Krastorio2='2.1.4'})
          assert(result.extended_effects==0 and #row.effects==1)
          package.preload['compatibility.modern_catalogue.k2so']=nil
          row,result=run({['space-age']='2.1.23',Krastorio2='2.1.4',
            ['Krastorio2-spaced-out']='2.0.19',Krastorio2Assets='2.1.0',['k2so-assets']='1.0.7'})
          assert(result.extended_effects==2 and #row.effects==3)
          assert(row.effects[2].recipe=='cooling' and row.effects[2].change==.15)
          assert(row.effects[3].recipe=='producer' and row.effects[3].change==.15)
        ''')

    def test_inactive_space_age_and_literal_families_do_not_read_pattern_classes(self):
        self.lua.execute(r'''
          local source=raw_with_recipes({gear=recipe({}, {product('item','iron-gear-wheel')})})
          setmetatable(source, {__index=function(_,key) error('unexpected item class read: ' .. key) end})
          local gear=generated('research_gears', {productivity('known',.1)})
          local soil=generated('research_artificial_soil', {productivity('known-soil',.1)})
          local result=extension.extend({gear,soil}, {effect_percent=10,
            streams={research_artificial_soil={effect_percent=10}}}, {raw=source, mods={}})
          assert(result.extended_effects == 1 and result.work.items == 0)
          assert(#soil.effects == 1)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(ProductTargetExtensionTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

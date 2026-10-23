"""Independent host controls for the first native research slice (Lua 5.2)."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]

MODERN_ORACLE = json.loads(
    (ROOT / "spec/mir5/inventory/modern-f210-470.json").read_text(encoding="utf-8")
)

# Exact data-raw rows retained from the accepted published 4.7 F210 captures:
# vanilla inventory, Space Age capture, and K2SO capture respectively. Keeping
# them here makes this host control portable; it does not read local build data.
FROZEN_GEAR_ROWS = json.loads(r'''{
  "vanilla": {"type":"technology","name":"recipe-prod-research_gears-1","icons":[{"icon":"__base__/graphics/icons/iron-gear-wheel.png","icon_size":64},{"icon":"__core__/graphics/icons/technology/constants/constant-recipe-productivity.png","icon_size":128,"scale":0.5,"shift":[50,50],"floating":true}],"level":1,"localised_name":["technology-name.more-infinite-research.research_gears",["item-name.iron-gear-wheel"]],"localised_description":["technology-description.more-infinite-research.recipe_productivity"],"upgrade":true,"max_level":"infinite","order":"p[research_gears]","prerequisites":["automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"],"effects":[{"type":"change-recipe-productivity","recipe":"iron-gear-wheel","change":0.1}],"unit":{"count_formula":"8000*2^(L-1)","time":60,"ingredients":[["automation-science-pack",1],["logistic-science-pack",1],["chemical-science-pack",1],["production-science-pack",1]]}},
  "space_age": {"type":"technology","name":"recipe-prod-research_gears-1","icons":[{"icon":"__base__/graphics/icons/iron-gear-wheel.png","icon_size":64},{"icon":"__core__/graphics/icons/technology/constants/constant-recipe-productivity.png","icon_size":128,"scale":0.5,"shift":[50,50],"floating":true}],"level":1,"localised_name":["technology-name.more-infinite-research.research_gears",["item-name.iron-gear-wheel"]],"localised_description":["technology-description.more-infinite-research.recipe_productivity"],"upgrade":true,"max_level":"infinite","order":"p[research_gears]","prerequisites":["automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"],"effects":[{"type":"change-recipe-productivity","recipe":"casting-iron-gear-wheel","change":0.1},{"type":"change-recipe-productivity","recipe":"iron-gear-wheel","change":0.1}],"unit":{"count_formula":"8000*2^(L-1)","time":60,"ingredients":[["automation-science-pack",1],["logistic-science-pack",1],["chemical-science-pack",1],["production-science-pack",1]]}},
  "k2so": {"type":"technology","name":"recipe-prod-research_gears-1","icons":[{"icon":"__Krastorio2Assets__/icons/items/iron-gear-wheel.png","icon_size":64},{"icon":"__core__/graphics/icons/technology/constants/constant-recipe-productivity.png","icon_size":128,"scale":0.5,"shift":[50,50],"floating":true}],"level":1,"localised_name":["technology-name.more-infinite-research.research_gears",["item-name.iron-gear-wheel"]],"localised_description":["technology-description.more-infinite-research.recipe_productivity"],"upgrade":true,"max_level":"infinite","order":"p[research_gears]","prerequisites":["automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"],"effects":[{"type":"change-recipe-productivity","recipe":"casting-iron-gear-wheel","change":0.1},{"type":"change-recipe-productivity","recipe":"iron-gear-wheel","change":0.1},{"type":"change-recipe-productivity","recipe":"kr-iron-gear-wheel-from-enriched-iron","change":0.1},{"type":"change-recipe-productivity","recipe":"kr-iron-gear-wheel-from-iron-ore","change":0.1}],"unit":{"count_formula":"8000*2^(L-1)","time":60,"ingredients":[["automation-science-pack",1],["logistic-science-pack",1],["chemical-science-pack",1],["production-science-pack",1]]}}
}''')


def lua_table(lua, value):
    if isinstance(value, dict):
        table = lua.table()
        for key, item in value.items():
            table[key] = lua_table(lua, item)
        return table
    if isinstance(value, list):
        table = lua.table()
        for index, item in enumerate(value, 1):
            table[index] = lua_table(lua, item)
        return table
    return value


def plain_lua(value):
    if not hasattr(value, "items"):
        return value
    items = dict(value.items())
    numeric = sorted(key for key in items if isinstance(key, int))
    if len(numeric) == len(items) and numeric == list(range(1, len(items) + 1)):
        return [plain_lua(items[index]) for index in numeric]
    return {key: plain_lua(item) for key, item in items.items()}


K2SO_MODS = {
    "space-age": "2.1.23", "Krastorio2": "2.1.4", "Krastorio2-spaced-out": "2.0.19",
    "Krastorio2Assets": "2.1.0", "k2so-assets": "1.0.7",
}


def profile_mods(identifier):
    if identifier == "base-f210":
        return {}
    if identifier == "space-age-f210":
        return {"space-age": "2.1.23"}
    if identifier == "k2so-f210":
        return K2SO_MODS
    raise AssertionError(f"unknown published profile: {identifier}")


def host_row(row):
    """Map the two empty Lua prerequisite tables to Lupa's list view only."""
    output = json.loads(json.dumps(row))
    if (output.get("name") in {"mir-k2-imersite-staged-state-1", "mir-k2-imersite-continuation-state-4"}
            and output.get("prerequisites") == {}):
        output["prerequisites"] = []
    return output


def intended_setting_rows(profile):
    """Apply only the exact planner-field retirement named by the oracle."""
    records = profile["published_output"]["settings"]["additions"]
    retirements = {
        (item["type"], item["name"], item["field"]): item
        for item in profile["intended_player_output"]["settings"]["remove_published_fields"]
    }
    expected = {}
    for item in records:
        row = json.loads(json.dumps(item["row"]))
        key = (item["type"], item["name"], "targets")
        retirement = retirements.pop(key, None)
        if "targets" in row:
            if retirement is None:
                raise AssertionError(f"oracle lacks targets retirement for {item['name']}")
            if (retirement["reason"] != "MIR4 planner-only target metadata has no Factorio setting or MIR5 runtime consumer"
                    or retirement["provenance"] != "published-4.7 setting descriptor targets field"):
                raise AssertionError(f"oracle has an invalid targets retirement for {item['name']}")
            row.pop("targets")
        elif retirement is not None:
            raise AssertionError(f"oracle retires absent targets for {item['name']}")
        expected[item["name"]] = row
    if retirements:
        raise AssertionError(f"oracle retires fields outside published settings: {sorted(retirements)}")
    return expected


class GeneratorTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          config = require("research.settings")
          productivity = require("research.productivity")
          cost = require("research.cost")
          gear_bindings = require("compatibility.gear_bindings")
          generator = require("research.generator")
          modern_catalogue = require("compatibility.modern_catalogue")
          modern = require("research.modern")
          function defaults()
            local values = {}
            for _, spec in ipairs(config.prototypes()) do values[spec.name] = {value = spec.default_value} end
            return values
          end
          function build()
            return productivity.gears(config.resolve(defaults()))
          end
          function world()
            local packs = {}
            for _, name in ipairs({"automation", "logistic", "chemical", "production"}) do
              packs[name .. "-science-pack"] = {}
            end
            return {raw = {technology = packs, tool = packs, recipe = {["iron-gear-wheel"] = {}}},
              writes = 0, extend = function(self, values) self.writes = self.writes + 1; self.emitted = values end}
          end
          function refused(prototypes, environment, fragment)
            local ok, message = pcall(generator.install, prototypes, environment)
            assert(not ok, "invalid family was accepted")
            assert(environment.writes == 0, "preflight rejection wrote prototypes")
            assert(tostring(message):find(fragment, 1, true), tostring(message))
          end
          -- Test fixture construction follows only the explicit authored
          -- selection; it never enumerates data.raw to make a family pass.
          function full_world(active_mods)
            local tools, technologies, recipes = {}, {}, {}
            local function add_technology(name) if name then technologies[name] = technologies[name] or {} end end
            local function add_science(key)
              for _, name in ipairs(modern_catalogue.science_names(key)) do
                tools[name] = {}; add_technology(name)
              end
            end
            local selected = modern_catalogue.select(active_mods or {})
            for _, definition in ipairs(selected.definitions) do
              add_science(definition.science)
              for _, name in ipairs(definition.prerequisites) do add_technology(name) end
              for _, effect in ipairs(definition.effects) do if effect.recipe then recipes[effect.recipe] = {} end end
            end
            for _, definition in ipairs(selected.continuations) do
              add_science(definition.science)
              for _, name in ipairs(definition.prerequisites) do add_technology(name) end
            end
            if selected.k2_imersite then
              add_science("science_automation_logistic_chemical_production")
              add_science("science_production_space")
              add_technology("kr-quarry-minerals-extraction")
              recipes["kr-imersite-powder"] = {}
            end
            for _, name in ipairs({"automation", "logistic", "chemical", "production", "military", "utility", "space", "agricultural", "electromagnetic", "cryogenic", "metallurgic", "promethium"}) do
              tools[name .. "-science-pack"] = {}; add_technology(name .. "-science-pack")
            end
            recipes["iron-gear-wheel"] = {}
            if active_mods and active_mods["space-age"] then
              recipes["casting-iron-gear-wheel"] = {}; technologies["agriculture"] = {}; technologies["spoilage"] = {}
            end
            if modern_catalogue.is_k2so(active_mods) then
              recipes["kr-iron-gear-wheel-from-enriched-iron"] = {}; recipes["kr-iron-gear-wheel-from-iron-ore"] = {}
            end
            local lab_inputs = {}
            for name in pairs(tools) do lab_inputs[#lab_inputs + 1] = name end
            table.sort(lab_inputs)
            return {raw = {technology = technologies, tool = tools, item = {spoilage = {}}, recipe = recipes,
              lab = {fixture = {inputs=lab_inputs}}}, writes = 0,
              extend = function(self, values) self.writes = self.writes + 1; self.emitted = values end}
          end
          function bound_output(active_mods, recipe_rows)
            local binding = gear_bindings.select(active_mods, {recipe = recipe_rows})
            return productivity.gears(config.resolve(defaults()), binding)
          end
          function disabled_data_final()
            mods = {['space-age'] = '2.1.23'}
            package.loaded["research.settings"] = nil
            local space_config = require("research.settings")
            local startup = {}
            for _, spec in ipairs(space_config.prototypes()) do startup[spec.name] = {value = spec.default_value} end
            local environment = full_world(mods)
            startup["ips-enable-research_gears"].value = false
            settings, data, helpers, log = {startup = startup}, environment, nil, function() end
            package.loaded["compatibility.gear_bindings"] = nil
            package.preload["compatibility.gear_bindings"] = function() error("inactive binding was loaded") end
            local ok, message = pcall(dofile, data_final_path)
            package.preload["compatibility.gear_bindings"] = nil
            package.loaded["compatibility.gear_bindings"] = gear_bindings
            return ok, message, environment
          end
          function missing_active_space_age_binding()
            local startup, environment = defaults(), world()
            settings, mods, data, helpers, log = {startup = startup}, {['space-age'] = '2.1.23'}, environment, nil, function() end
            local ok, message = pcall(dofile, data_final_path)
            return ok, message, environment
          end
        ''')
        self.lua.globals().data_final_path = (ROOT / "source/mir5/data-final-fixes.lua").as_posix()

    def test_published_default_and_detachment(self):
        self.lua.execute('''
          local a, b = build(), build()
          assert(a.name == "recipe-prod-research_gears-1" and a.max_level == "infinite" and a.upgrade)
          assert(a.order == "p[research_gears]")
          assert(a.unit.count_formula == "8000*2^(L-1)" and a.unit.time == 60)
          assert(#a.unit.ingredients == 4 and #a.prerequisites == 4)
          local expected = {"automation", "logistic", "chemical", "production"}
          for index, name in ipairs(expected) do
            assert(a.unit.ingredients[index][1] == name .. "-science-pack")
            assert(a.unit.ingredients[index][2] == 1 and a.prerequisites[index] == name .. "-science-pack")
          end
          assert(#a.effects == 1 and a.effects[1].type == "change-recipe-productivity")
          assert(a.effects[1].recipe == "iron-gear-wheel" and a.effects[1].change == .10)
          a.effects[1].change = 99; a.unit.ingredients[1][2] = 99; a.prerequisites[1] = "changed"
          assert(b.effects[1].change == .10 and b.unit.ingredients[1][2] == 1)
          assert(b.prerequisites[1] == "automation-science-pack")
        ''')

    def test_approved_profile_bindings_match_frozen_full_native_rows(self):
        profiles = {
            "vanilla": ({}, ["iron-gear-wheel"]),
            "space_age": ({"space-age": "2.1.23"}, ["casting-iron-gear-wheel", "iron-gear-wheel"]),
            "k2so": ({
                "space-age": "2.1.23", "Krastorio2": "2.1.4",
                "Krastorio2-spaced-out": "2.0.19", "Krastorio2Assets": "2.1.0",
                "k2so-assets": "1.0.7",
            }, [
                "casting-iron-gear-wheel", "iron-gear-wheel",
                "kr-iron-gear-wheel-from-enriched-iron", "kr-iron-gear-wheel-from-iron-ore",
            ]),
        }
        for profile, (mods, recipes) in profiles.items():
            recipe_rows = {name: {} for name in recipes}
            self.lua.globals().profile_mods = lua_table(self.lua, mods)
            self.lua.globals().profile_recipes = lua_table(self.lua, recipe_rows)
            actual = self.lua.eval("bound_output(profile_mods, profile_recipes)")
            self.assertEqual(plain_lua(actual), FROZEN_GEAR_ROWS[profile], profile)

    def test_profile_bindings_are_detached_direct_and_fail_closed(self):
        self.lua.execute('''
          local unrelated_reads = 0
          local recipes = setmetatable({
            ["casting-iron-gear-wheel"] = {}, ["iron-gear-wheel"] = {},
            ["kr-iron-gear-wheel-from-enriched-iron"] = {}, ["kr-iron-gear-wheel-from-iron-ore"] = {}
          }, {__pairs = function() error("whole recipe enumeration") end,
              __index = function() unrelated_reads = unrelated_reads + 1; error("unrelated recipe read") end})
          local mods = {['Krastorio2'] = '2.1.4', ['Krastorio2-spaced-out'] = '2.0.19',
            ['Krastorio2Assets'] = '2.1.0', ['k2so-assets'] = '1.0.7', ['space-age'] = '2.1.23'}
          local first = gear_bindings.select(mods, {recipe = recipes})
          assert(unrelated_reads == 0, "binding inspected an unrelated recipe")
          first.recipes[1] = "foreign"
          local second = gear_bindings.select(mods, {recipe = recipes})
          assert(second.recipes[1] == "casting-iron-gear-wheel")
          local a, b = productivity.gears(config.resolve(defaults()), second), productivity.gears(config.resolve(defaults()), second)
          a.effects[1].recipe = "foreign"; assert(b.effects[1].recipe == "casting-iron-gear-wheel")
          local partial = {['Krastorio2'] = '2.1.4'}
          assert(not pcall(gear_bindings.select, partial, {recipe = recipes}))
          local no_space_age = {['Krastorio2'] = '2.1.4', ['Krastorio2-spaced-out'] = '2.0.19',
            ['Krastorio2Assets'] = '2.1.0', ['k2so-assets'] = '1.0.7'}
          assert(not pcall(gear_bindings.select, no_space_age, {recipe = recipes}))
          local incomplete = {['space-age'] = '2.1.23'}
          assert(not pcall(gear_bindings.select, incomplete, {recipe = {['iron-gear-wheel'] = {}}}))
        ''')

    def test_vanilla_selection_does_not_load_inactive_profile_bodies(self):
        self.lua.execute('''
          local space_age = "compatibility.gear_bindings.space_age"
          local k2so = "compatibility.gear_bindings.k2so"
          package.loaded[space_age], package.loaded[k2so] = nil, nil
          package.preload[space_age] = function() error("inactive Space Age profile was loaded") end
          package.preload[k2so] = function() error("inactive K2SO profile was loaded") end
          local binding = gear_bindings.select({}, {recipe = {['iron-gear-wheel'] = {}}})
          assert(binding.profile == "vanilla-f210" and binding.recipes[1] == "iron-gear-wheel")
          assert(package.loaded[space_age] == nil and package.loaded[k2so] == nil,
            "vanilla selection loaded an inactive profile body")
          package.preload[space_age], package.preload[k2so] = nil, nil
        ''')

    def test_data_stage_defers_inactive_binding_and_preflights_active_profile(self):
        self.lua.execute('''
          local ok, message, environment = disabled_data_final()
          assert(ok, message); assert(environment.writes == 1 and #environment.emitted == 71 and environment.emitted[1].enabled == false)
          ok, message, environment = missing_active_space_age_binding()
          assert(not ok and tostring(message):find("missing required recipe casting-iron-gear-wheel", 1, true), tostring(message))
          assert(environment.writes == 0, "active binding wrote before named preflight")
        ''')

    def test_full_modern_catalogue_is_lazy_bounded_and_declares_exact_owners(self):
        self.lua.execute('''
          -- Base construction must not require the inactive Space Age body.
          local space_body = "compatibility.modern_catalogue.space_age"
          package.loaded[space_body] = nil
          package.preload[space_body] = function() error("base selection loaded Space Age catalogue") end
          local base = modern_catalogue.select({})
          assert(base.profile == "base" and #base.definitions == 46
            and #base.continuations == 6 and #base.recipe_patches == 0)
          local base_rows = modern.technologies(base, config.resolve(defaults()))
          assert(#base_rows == 52 and package.loaded[space_body] == nil)
          local ids = {}; for _, row in ipairs(base_rows) do ids[row.name] = row end
          assert(ids["recipe-prod-research_advanced_circuit-1"].effects[1].recipe == "advanced-circuit")
          assert(ids["braking-force-8"].unit.count_formula == "861.51212960553*1.33333^(L-8)")
          assert(ids["inserter-capacity-bonus-8"].effects[1].modifier == 2
            and ids["worker-robots-storage-4"].effects[1].modifier == 1)
          package.preload[space_body] = nil

          local space_mods = {['space-age'] = '2.1.23'}
          local space = modern_catalogue.select(space_mods)
          assert(space.profile == "space-age" and #space.definitions == 62
            and #space.continuations == 6 and #space.recipe_patches == 3)
          local outputs = modern.technologies(space, config.resolve(defaults()))
          local present = {}; for _, row in ipairs(outputs) do present[row.name] = row end
          assert(#outputs == 68 and present["recipe-prod-research_low_density_structure-1"] == nil)
          assert(present["recipe-prod-research_artificial_soil-1"].effects[3].change == .05)
          assert(present["research-speed-7"].prerequisites[1] == "research-speed-5")
          local recipes = {['capture-robot-rocket'] = {}, ['ice-platform'] = {}, ['space-platform-foundation'] = {}}
          modern.preflight_recipe_patches(space, {recipe = recipes})
          modern.apply_recipe_patches(space, {recipe = recipes})
          assert(recipes['capture-robot-rocket'].allow_productivity and recipes['ice-platform'].allow_productivity
            and recipes['space-platform-foundation'].allow_productivity)
          space.definitions[1].effects[1].recipe = "foreign"
          assert(modern_catalogue.select(space_mods).definitions[1].effects[1].recipe ~= "foreign")

          -- The runtime admission list is a fresh, named declaration rather
          -- than a scan of output tables. Every declared family has a setting.
          mods = {}
          package.loaded["research.catalogue"] = nil
          local base_declared = require("research.catalogue").declared()
          assert(#base_declared == 53)
          for _, row in ipairs(base_declared) do
            assert(config.resolve(defaults()).streams[row.family] ~= nil)
            assert(row.legacy_binding and row.legacy_binding.source and row.legacy_binding.operation)
          end
          mods = space_mods
          package.loaded["research.catalogue"] = nil
          local space_declared = require("research.catalogue").declared()
          local owners = 0
          for _, row in ipairs(space_declared) do
            if row.ownership_kind == "nativeowner" then
              owners = owners + 1
              assert(row.native_owner_identity == row.id and row.native_admission)
              assert(row.legacy_binding.source == "native-owner"
                and row.legacy_binding.operation == "preserve_native_owner")
            end
          end
          assert(#space_declared == 76 and owners == 5)
        ''')

    def test_native_owner_settings_keep_zero_time_as_native_inherit_only_for_active_owners(self):
        self.lua.execute('''
          local function startup_for(configuration)
            local startup = {}
            for _, spec in ipairs(configuration.prototypes()) do startup[spec.name] = {value = spec.default_value} end
            return startup
          end

          mods = {['space-age'] = '2.1.23'}
          package.loaded["research.settings"] = nil
          local space_settings = require("research.settings")
          local startup = startup_for(space_settings)
          startup["ips-research-time-research_low_density_structure"].value = 0
          local space = space_settings.resolve(startup)
          local owner = space.streams.research_low_density_structure
          assert(owner.research_time == 0 and owner.configured.research_time,
            "Space Age native owner lost its documented inherit sentinel")

          mods = {}
          package.loaded["research.settings"] = nil
          local base_settings = require("research.settings")
          startup = startup_for(base_settings)
          startup["ips-research-time-research_low_density_structure"].value = 0
          local base = base_settings.resolve(startup)
          assert(base.streams.research_low_density_structure.research_time == 60
            and base.streams.research_low_density_structure.configured.research_time,
            "ordinary emitted research changed the zero-time meaning")
        ''')

    def test_native_owner_patches_are_atomic_profile_bound_and_preserve_unowned_fields(self):
        self.lua.execute('''
          local function owner_fixture(definitions)
            local owners = {}
            for _, definition in ipairs(definitions) do
              local effects = {{type = "foreign-effect", recipe = "foreign", change = 7}}
              for _, recipe in ipairs(definition.admission.recipes) do
                effects[#effects + 1] = {type = definition.admission.effect_type, recipe = recipe,
                  change = definition.expected.effect_change}
              end
              owners[definition.id] = {name = definition.id, max_level = definition.expected.max_level,
                unit = {count_formula = definition.expected.count_formula, time = definition.expected.research_time,
                  ingredients = {{"foreign-science", 1}}, foreign_unit_field = "preserve"},
                effects = effects, foreign_top_level_field = "preserve"}
            end
            return owners
          end
          local function owner_values(definitions)
            local values = {streams = {}}
            for _, definition in ipairs(definitions) do
              values.streams[definition.family] = {enabled = true, base_cost = definition.expected.base_cost,
                linear_increment = definition.expected.linear_increment, growth_factor = definition.expected.growth_factor,
                research_time = definition.expected.research_time, effect_percent = definition.expected.effect_change * 100,
                configured = {}}
            end
            return values
          end
          local function assert_named_changes(owner, definition, value)
            assert(owner.foreign_top_level_field == "preserve" and owner.unit.foreign_unit_field == "preserve")
            assert(owner.effects[1].type == "foreign-effect" and owner.effects[1].change == 7)
            local named = {}
            for _, effect in ipairs(owner.effects) do named[effect.recipe] = effect end
            for _, recipe in ipairs(definition.admission.recipes) do
              assert(named[recipe].change == value)
            end
          end

          local space = modern_catalogue.select({['space-age'] = '2.1.23'})
          local owners, values = owner_fixture(space.native_owners), owner_values(space.native_owners)
          for _, definition in ipairs(space.native_owners) do
            values.streams[definition.family].effect_percent = 20
            values.streams[definition.family].configured.effect_percent = true
          end
          local first = space.native_owners[1]
          values.streams[first.family].base_cost = 200
          values.streams[first.family].linear_increment = 3
          values.streams[first.family].growth_factor = 2
          values.streams[first.family].research_time = 0
          values.streams[first.family].configured.base_cost = true
          values.streams[first.family].configured.linear_increment = true
          values.streams[first.family].configured.research_time = true
          values.streams[first.family].max_level = 7
          values.streams[first.family].configured.max_level = true
          local second = space.native_owners[2]
          values.streams[second.family].research_time = 123
          values.streams[second.family].configured.research_time = true
          local original_unit, original_effects = owners[first.id].unit, owners[first.id].effects
          local patches = modern.preflight_native_owner_patches(space, {technology = owners}, values)
          assert(#patches == 5 and owners[first.id].unit == original_unit and owners[first.id].effects == original_effects)
          modern.apply_native_owner_patches(patches)
          assert(owners[first.id].unit.count_formula == "(200+3*(L-1))*2^(L-1)"
            and owners[first.id].unit.time == 60 and owners[first.id].unit ~= original_unit
            and owners[first.id].max_level == "infinite")
          assert(owners[second.id].unit.time == 123, "positive owner research time was not applied")
          for _, definition in ipairs(space.native_owners) do assert_named_changes(owners[definition.id], definition, .2) end

          -- Every selected patch is checked before any owner table is changed.
          owners, values = owner_fixture(space.native_owners), owner_values(space.native_owners)
          for _, definition in ipairs(space.native_owners) do
            values.streams[definition.family].configured.effect_percent = true
            values.streams[definition.family].effect_percent = 20
          end
          owners[space.native_owners[2].id].effects[2].change = .2
          local ok, message = pcall(modern.preflight_native_owner_patches, space, {technology = owners}, values)
          assert(not ok and tostring(message):find("unexpected effect change", 1, true), tostring(message))
          assert(owners[space.native_owners[1].id].effects[2].change == .1,
            "a later malformed owner allowed an earlier patch")

          -- Disabling an owner preserves the established owner even when a
          -- stale non-default setting value is also present.
          owners, values = owner_fixture(space.native_owners), owner_values(space.native_owners)
          values.streams[first.family].enabled = false
          values.streams[first.family].effect_percent = 20
          values.streams[first.family].configured.effect_percent = true
          owners[first.id].unit.count_formula = "foreign-owner-formula"
          patches = modern.preflight_native_owner_patches(space, {technology = owners}, values)
          assert(#patches == 0 and owners[first.id].unit.count_formula == "foreign-owner-formula")

          local k2mods = {['space-age'] = '2.1.23', Krastorio2 = '2.1.4',
            ['Krastorio2-spaced-out'] = '2.0.19', Krastorio2Assets = '2.1.0', ['k2so-assets'] = '1.0.7'}
          local k2 = modern_catalogue.select(k2mods)
          owners, values = owner_fixture(k2.native_owners), owner_values(k2.native_owners)
          for _, definition in ipairs(k2.native_owners) do
            values.streams[definition.family].effect_percent = 25
            values.streams[definition.family].configured.effect_percent = true
          end
          modern.apply_native_owner_patches(modern.preflight_native_owner_patches(k2, {technology = owners}, values))
          assert(#k2.native_owners == 4 and owners["steel-plate-productivity"] == nil)
          for _, definition in ipairs(k2.native_owners) do assert_named_changes(owners[definition.id], definition, .25) end
        ''')

    def test_data_final_preflights_nondefault_native_owners_before_emitting(self):
        self.lua.execute('''
          local function add_native_owners(environment, definitions)
            for _, definition in ipairs(definitions) do
              local effects = {}
              for _, recipe in ipairs(definition.admission.recipes) do
                effects[#effects + 1] = {type = definition.admission.effect_type, recipe = recipe,
                  change = definition.expected.effect_change}
              end
              environment.raw.technology[definition.id] = {max_level = definition.expected.max_level,
                unit = {count_formula = definition.expected.count_formula, time = definition.expected.research_time}, effects = effects}
            end
          end
          mods = {['space-age'] = '2.1.23'}
          package.loaded["research.settings"] = nil
          local space_settings = require("research.settings")
          local startup, selected = {}, modern_catalogue.select(mods)
          for _, spec in ipairs(space_settings.prototypes()) do startup[spec.name] = {value = spec.default_value} end
          startup["ips-effect-per-level-research_low_density_structure"].value = 20
          startup["ips-effect-per-level-research_plastic"].value = 20
          local environment = full_world(mods)
          add_native_owners(environment, selected.native_owners)
          environment.raw.technology["plastic-bar-productivity"].effects[1].change = .2
          settings, data, helpers, log = {startup = startup}, environment, nil, function() end
          local ok, message = pcall(dofile, data_final_path)
          assert(not ok and tostring(message):find("native-owner preflight", 1, true), tostring(message))
          assert(environment.writes == 0, "native-owner failure emitted technologies")
          assert(environment.raw.technology["low-density-structure-productivity"].effects[1].change == .1,
            "native-owner failure applied an earlier owner patch")
        ''')

    def test_science_policy_is_applied_to_the_whole_owned_catalogue_before_publication(self):
        self.lua.execute('''
          settings, mods, helpers, log = {startup=defaults()}, {}, nil, function() end
          settings.startup["ips-require-space-gate"].value = true
          settings.startup["mir-science-pack-ingredient-policy"].value = "space"
          data = full_world(mods)
          local foreign = setmetatable({}, {__index=function() error("foreign research inspected") end})
          data.raw.technology["Space-Lab-Research-61"] = foreign
          local reads = 0
          local labs = data.raw.lab
          data.raw.lab = setmetatable({}, {__pairs=function()
            reads = reads + 1; return next,labs,nil
          end})
          assert(dofile(data_final_path) == nil and data.writes == 1 and #data.emitted == 53)
          assert(reads == 1 and data.raw.technology["Space-Lab-Research-61"] == foreign)
          for _, row in ipairs(data.emitted) do
            local pack, gate = false, false
            for _, ingredient in ipairs(row.unit.ingredients) do pack = pack or ingredient[1] == "space-science-pack" end
            for _, name in ipairs(row.prerequisites) do gate = gate or name == "space-science-pack" end
            assert(pack and gate and row.enabled ~= false, row.name)
          end
        ''')

    def test_lab_skip_retains_disabled_owned_identities_and_foreign_research(self):
        self.lua.execute('''
          settings, mods, helpers, log = {startup=defaults()}, {}, nil, function() end
          settings.startup["mir-lab-incompatibility-policy"].value = "skip"
          data = full_world(mods)
          data.raw.lab = {restricted={inputs={"automation-science-pack"}}}
          local foreign = {enabled=true,foreign=77}
          data.raw.technology["foreign"] = foreign
          assert(dofile(data_final_path) == nil and data.writes == 1 and #data.emitted == 53)
          for _, row in ipairs(data.emitted) do assert(row.enabled == false and #row.unit.ingredients > 0) end
          assert(data.raw.technology.foreign == foreign and foreign.enabled and foreign.foreign == 77)
        ''')

    def test_weapon_speed_overlap_requires_an_enabled_positive_direct_replacement(self):
        self.lua.execute('''
          local function outputs(value, enabled)
            local direct = {name = "recipe-prod-direct-1",
              effects = {{type = "gun-speed", ammo_category = "bullet", modifier = value}}}
            if not enabled then direct.enabled = false end
            return {
              direct,
              {name = "weapon-shooting-speed-7", effects = {
                {type = "gun-speed", ammo_category = "bullet", modifier = .4},
                {type = "gun-speed", ammo_category = "shotgun-shell", modifier = .4},
                {type = "laboratory-speed", modifier = .1},
              }},
            }
          end
          local selection = {definitions = {{key = "direct", family = "research_cannon_shooting_speed"}}}
          local function values(mode, enabled)
            return {options = {["mir-adjust-vanilla-weapon-speed-techs"] = mode},
              streams = {research_cannon_shooting_speed = {enabled = enabled}}}
          end
          local rows = outputs(.1, true)
          modern.apply_weapon_speed_overlap(selection, rows, values("off", true))
          assert(#rows[2].effects == 3)
          for _, mode in ipairs({"only-when-dedicated-tech-enabled", "always"}) do
            rows = outputs(.1, true)
            modern.apply_weapon_speed_overlap(selection, rows, values(mode, true))
            assert(#rows[2].effects == 2 and rows[2].effects[1].ammo_category == "shotgun-shell"
              and rows[2].effects[2].type == "laboratory-speed")
          end
          rows = outputs(.1, false)
          modern.apply_weapon_speed_overlap(selection, rows, values("always", false))
          assert(#rows[2].effects == 3, "always removed a paid effect without an enabled owner")
          rows = outputs(0, true)
          modern.apply_weapon_speed_overlap(selection, rows, values("only-when-dedicated-tech-enabled", true))
          assert(#rows[2].effects == 3, "zero direct effect removed a paid effect")

          -- The captured defaults have no overlapping direct category, so the
          -- policy is inert for the exact published Base output.
          local selected = modern_catalogue.select({})
          local generated = modern.technologies(selected, config.resolve(defaults()))
          modern.apply_weapon_speed_overlap(selected, generated, config.resolve(defaults()))
          for _, technology in ipairs(generated) do
            if technology.name == "weapon-shooting-speed-7" then
              assert(#technology.effects == 2 and technology.effects[1].ammo_category == "bullet"
                and technology.effects[2].ammo_category == "shotgun-shell")
            end
          end

          local k2mods = {['space-age'] = '2.1.23', Krastorio2 = '2.1.4',
            ['Krastorio2-spaced-out'] = '2.0.19', Krastorio2Assets = '2.1.0', ['k2so-assets'] = '1.0.7'}
          mods = k2mods
          package.loaded["research.settings"] = nil
          local k2settings, startup = require("research.settings"), {}
          for _, spec in ipairs(k2settings.prototypes()) do startup[spec.name] = {value = spec.default_value} end
          selected = modern_catalogue.select(k2mods)
          generated = modern.technologies(selected, k2settings.resolve(startup))
          modern.apply_weapon_speed_overlap(selected, generated, k2settings.resolve(startup))
          for _, technology in ipairs(generated) do
            if technology.name == "weapon-shooting-speed-7" then
              assert(#technology.effects == 7 and technology.effects[1].ammo_category == "bullet"
                and technology.effects[7].ammo_category == "kr-heavy-rocket",
                "unexpected K2 weapon continuation: " .. #technology.effects .. ":"
                  .. tostring(technology.effects[1].ammo_category) .. ":"
                  .. tostring(technology.effects[#technology.effects].ammo_category))
            end
          end
        ''')

    def test_k2so_catalogue_keeps_exact_imersite_stages_and_owners_lazy(self):
        self.lua.execute('''
          local k2_body = "compatibility.modern_catalogue.k2so"
          package.loaded[k2_body] = nil
          package.preload[k2_body] = function() error("inactive K2SO catalogue loaded") end
          assert(modern_catalogue.select({}).profile == "base")
          assert(package.loaded[k2_body] == nil, "base selection loaded K2SO catalogue")
          package.preload[k2_body] = nil

          local k2mods = {['space-age'] = '2.1.23', Krastorio2 = '2.1.4',
            ['Krastorio2-spaced-out'] = '2.0.19', Krastorio2Assets = '2.1.0', ['k2so-assets'] = '1.0.7'}
          assert(modern_catalogue.is_k2so(k2mods) and not modern_catalogue.is_k2so({Krastorio2 = '2.1.4'}))
          local selected = modern_catalogue.select(k2mods)
          assert(selected.profile == "k2so-f210" and selected.k2_imersite
            and #selected.definitions == 62 and #selected.continuations == 6 and #selected.recipe_patches == 3)
          assert(#modern_catalogue.native_owners(k2mods) == 4)
          local has_steel = false
          for _, owner in ipairs(modern_catalogue.native_owners(k2mods)) do
            if owner.id == "steel-plate-productivity" then has_steel = true end
          end
          assert(not has_steel, "K2SO retained the absent steel native-owner admission")
          local owners = {}
          for _, owner in ipairs(modern_catalogue.native_owners(k2mods)) do owners[owner.id] = owner end
          assert(owners["low-density-structure-productivity"].admission.recipes[2] == "casting-low-density-structure")
          assert(owners["plastic-bar-productivity"].admission.recipes[2] == "bioplastic")
          assert(owners["processing-unit-productivity"].admission.recipes[2] == "kr-bio-processing-circuit")
          assert(owners["rocket-fuel-productivity"].admission.recipes[4] == "kr-rocket-fuel-with-hydrogen-chloride")

          mods = k2mods
          package.loaded["research.settings"] = nil
          local k2config = require("research.settings")
          local startup = {}
          for _, spec in ipairs(k2config.prototypes()) do startup[spec.name] = {value = spec.default_value} end
          local visible = {research_material_black_paving=true, research_material_glass=true, research_material_imersite=true,
            research_material_rare_metals=true, research_material_silicon=true, research_material_white_paving=true}
          for _, spec in ipairs(k2config.prototypes()) do
            local family = spec.name:match("^ips%-%a+%-research_material_(.+)$")
            if family and visible["research_material_" .. family] then assert(spec.hidden == nil, spec.name .. " remains hidden") end
          end
          assert(startup["ips-max-level-research_material_imersite"].value == 0)
          local values = k2config.resolve(startup)
          assert(values.streams.research_material_imersite__continuation == values.streams.research_material_imersite)
          package.loaded["research.catalogue"] = nil
          local declared = require("research.catalogue").declared()
          assert(#declared == 77)
          local declared_ids, holder_ids = {}, { ["mir-k2-imersite-staged-state-1"] = true, ["mir-k2-imersite-continuation-state-4"] = true }
          for _, row in ipairs(declared) do
            assert(values.streams[row.family] ~= nil, "catalogue family has no resolved value: " .. row.family)
            assert(row.legacy_binding and row.legacy_binding.source and row.legacy_binding.operation)
            assert(not holder_ids[row.id], "migration holder entered caps catalogue")
            declared_ids[row.id] = row
          end
          assert(declared_ids["recipe-prod-research_material_imersite-1"].cap_setting == "ips-max-level-research_material_imersite")
          assert(declared_ids["recipe-prod-research_material_imersite-4"].family == "research_material_imersite__continuation")
          local rows = modern.technologies(selected, values)
          assert(#rows == 72)
          local by_id = {}; for _, row in ipairs(rows) do by_id[row.name] = row end
          local early = by_id["recipe-prod-research_material_imersite-1"]
          local continuation = by_id["recipe-prod-research_material_imersite-4"]
          local early_holder = by_id["mir-k2-imersite-staged-state-1"]
          local continuation_holder = by_id["mir-k2-imersite-continuation-state-4"]
          assert(early.level == 1 and early.max_level == 3 and early.effects[1].recipe == "kr-imersite-powder" and early.effects[1].change == .02)
          assert(early.unit.count_formula == "200*2^(L-1)" and early.unit.time == 30)
          assert(continuation.level == 4 and continuation.max_level == "infinite" and continuation.show_levels_info == false
            and continuation.visible_when_disabled and continuation.unit.count_formula == "1600+200*(L-4)")
          assert(continuation.effects[1].recipe == "kr-imersite-powder" and continuation.effects[1].change == .02)
          assert(by_id["laser-shooting-speed-8"].effects[1].modifier == .1
            and by_id["laser-shooting-speed-8"].effects[2].ammo_category == "kr-impulse-rifle")
          assert(by_id["weapon-shooting-speed-7"].effects[1].modifier == .15
            and by_id["weapon-shooting-speed-7"].effects[5].modifier == .2)
          assert(by_id["inserter-capacity-bonus-8"].unit.ingredients[6][1] == "agricultural-science-pack"
            and by_id["worker-robots-storage-4"].unit.ingredients[6][1] == "electromagnetic-science-pack")
          assert(by_id["recipe-prod-research_mining_drill-1"].effects[1].change == .2
            and by_id["recipe-prod-research_mining_drill-1"].effects[4].change == .05)
          assert(early_holder.hidden and early_holder.enabled and not early_holder.upgrade and early_holder.level == 1
            and continuation_holder.hidden and continuation_holder.enabled and not continuation_holder.upgrade and continuation_holder.level == 4)
          assert(early_holder.effects[1].recipe == "kr-imersite-powder" and early_holder.effects[1].change == .02
            and continuation_holder.effects[1].recipe == "kr-imersite-powder" and continuation_holder.effects[1].change == .02)
          local environment = full_world(k2mods)
          generator.install(rows, environment)
          assert(environment.writes == 1 and #environment.emitted == 72)
          environment = full_world(k2mods)
          settings, data, helpers, log = {startup = startup}, environment, nil, function() end
          assert(dofile(data_final_path) == nil)
          assert(environment.writes == 1 and #environment.emitted == 75)
          local final_ids = {}; for _, row in ipairs(environment.emitted) do final_ids[row.name] = row end
          assert(final_ids["recipe-prod-research_gears-1"] and final_ids["recipe-prod-research_agricultural_growth_speed-1"]
            and final_ids["recipe-prod-research_spoilage_preservation-1"] and final_ids["recipe-prod-research_material_imersite-4"])

          startup["ips-cost-base-research_material_imersite"].value = 300
          startup["ips-cost-linear-increment-research_material_imersite"].value = 10
          startup["ips-cost-growth-research_material_imersite"].value = 1.5
          startup["ips-research-time-research_material_imersite"].value = 40
          startup["ips-effect-per-level-research_material_imersite"].value = 3.5
          rows = modern.technologies(selected, k2config.resolve(startup)); by_id = {}
          for _, row in ipairs(rows) do by_id[row.name] = row end
          assert(by_id[early.name].unit.count_formula == "(300+10*(L-1))*1.5^(L-1)" and by_id[early.name].effects[1].change == .035)
          assert(by_id[continuation.name].unit.count_formula == "1113.75+300*(L-4)" and by_id[continuation.name].unit.time == 40)
          local contract = require("research.k2_imersite")
          assert(contract.schema == 1 and contract.storage_key == "mir_k2_imersite_state" and contract.effect.change == .02
            and #contract.carriers == 2 and contract.carriers[2].source_id == continuation.name)
          package.loaded["research.settings"] = nil
          mods = nil
        ''')

    def test_cost_variants_and_nonfinite(self):
        self.lua.execute('''
          assert(productivity.cost(100, 0, 1) == "100")
          assert(productivity.cost(100, 25, 1) == "100+25*(L-1)")
          assert(productivity.cost(100, 0, 1.5) == "100*1.5^(L-1)")
          assert(productivity.cost(100, 25, 1.5) == "(100+25*(L-1))*1.5^(L-1)")
          assert(not pcall(productivity.cost, 100, 0, math.huge))
          assert(not pcall(productivity.cost, 0/0, 0, 2))
          assert(not pcall(productivity.cost, 100, 0, 1001))
        ''')

    def test_continuation_cost_inheritance_uses_the_historical_l1_boundary(self):
        self.lua.execute('''
          local inherited = {base_cost=0, linear_increment=0, growth_factor=3.333333333333}
          assert(cost.continuation(inherited, 8, 600, 400) == "1999.986000042*3.33333^(L-8)")
          local floor = {base_cost=0, linear_increment=0, growth_factor=.5}
          assert(cost.continuation(floor, 8, 600, 400) == "600")
          local named_growth = {base_cost=0, linear_increment=0, growth_factor=0}
          assert(cost.continuation(named_growth, 8, 600, 400) == "900.00004921875*1.5^(L-8)")
          assert(not pcall(cost.continuation, inherited, 8, math.huge, 400))

          local selected, definition = modern_catalogue.select({}), nil
          for _, candidate in ipairs(selected.continuations) do
            if candidate.id == "inserter-capacity-bonus-8" then definition = candidate end
          end
          assert(definition)
          local values = config.resolve(defaults())
          values.streams[definition.family].base_cost = 0
          local output = modern.continuation(definition, values)
          assert(output.unit.count_formula == "1999.986000042*3.33333^(L-8)")
        ''')

    def test_import_precedence_false_zero_and_invalid_entries(self):
        self.lua.execute('''
          local startup = defaults()
          startup["ips-cost-base-research_gears"].value = 100
          startup["mir-settings-profile-import"].value = '{"schema":1}'
          local values = {schema=1, kind="mir-settings-profile", settings={
            ["ips-cost-base-research_gears"] = 8000, ["ips-enable-research_gears"] = false,
            ["ips-cost-linear-increment-research_gears"] = 0, ["ips-research-time-research_gears"] = 0,
            ["ips-cost-growth-research_gears"] = -1,
            ["mir-prototype-positive-power-floor"] = true}}
          local codec = {json_to_table=function() return values end, decode_string=function(s) return s end, encode_string=function(s) return s end}
          local result = config.resolve(startup, codec)
          assert(result.base_cost == 8000 and result.enabled == false and result.linear_increment == 0)
          assert(result.research_time == 60 and result.growth_factor == 2)
          assert(result.options["mir-prototype-positive-power-floor"] == true)
          startup["mir-settings-profile-import"].value = "MIRSET1:anything"
          assert(config.resolve(startup, codec).enabled == false)
          codec.json_to_table = function() error("malformed JSON") end
          assert(config.resolve(startup, codec).base_cost == 100)
        ''')

    def test_disabled_identity_and_finite_cap_preserve_native_tail(self):
        self.lua.execute('''
          local startup = defaults(); startup["ips-enable-research_gears"].value = false
          local a = productivity.gears(config.resolve(startup))
          assert(a.name == "recipe-prod-research_gears-1" and a.enabled == false and a.effects[1].change == .1)
          startup["ips-max-level-research_gears"].value = 10
          local capped = productivity.gears(config.resolve(startup))
          assert(capped.name == a.name and capped.max_level == "infinite" and capped.enabled == false)
          assert(capped.effects[1].change == .1 and capped.unit.count_formula == a.unit.count_formula)
        ''')

    def test_scripted_effect_rows_match_the_captured_space_age_contract(self):
        self.lua.execute('''
          mods = {['space-age'] = '2.1.23'}
          package.loaded["research.settings"] = nil
          package.loaded["research.settings.space_age_scripted"] = nil
          local space_config = require("research.settings")
          local startup = {}
          for _, spec in ipairs(space_config.prototypes()) do startup[spec.name] = {value = spec.default_value} end
          startup["ips-research-time-research_agricultural_growth_speed"].value = 0
          startup["ips-enable-research_spoilage_preservation"].value = false
          local values = space_config.resolve(startup)
          assert(values.agricultural_growth_speed.base_cost == 40000
            and values.agricultural_growth_speed.growth_factor == 1.5
            and values.agricultural_growth_speed.research_time == 90
            and values.agricultural_growth_speed.effect_percent == 1)
          assert(values.spoilage_preservation.base_cost == 50000
            and values.spoilage_preservation.research_time == 120
            and values.spoilage_preservation.enabled == false)

          local names = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
            "production-science-pack", "space-science-pack", "agricultural-science-pack",
            "electromagnetic-science-pack", "cryogenic-science-pack"}
          local science = {}
          for _, name in ipairs(names) do science[name] = {} end
          local raw = {technology = science, tool = science, item = {spoilage = {}}}
          local bindings = require("compatibility.space_age_scripted_effects").select(mods, raw)
          local direct = require("research.scripted_effects").technologies(values, bindings)
          local agriculture, spoilage = direct[1], direct[2]
          assert(agriculture.name == "recipe-prod-research_agricultural_growth_speed-1"
            and agriculture.level == 1 and agriculture.upgrade and agriculture.max_level == "infinite")
          assert(agriculture.enabled == nil and agriculture.order == "p[research_agricultural_growth_speed]")
          assert(agriculture.unit.count_formula == "40000*1.5^(L-1)" and agriculture.unit.time == 90)
          assert(agriculture.icons[1].icon == "__space-age__/graphics/technology/agriculture.png"
            and agriculture.icons[1].icon_size == 256)
          assert(#agriculture.prerequisites == 7 and #agriculture.unit.ingredients == 7)
          assert(agriculture.prerequisites[5] == "agricultural-science-pack"
            and agriculture.prerequisites[6] == "electromagnetic-science-pack")
          assert(agriculture.effects[1].type == "nothing"
            and agriculture.effects[1].effect_description[1]
              == "modifier-description.more-infinite-research.agricultural_growth_speed"
            and agriculture.effects[1].effect_description[2] == "1")
          assert(spoilage.name == "recipe-prod-research_spoilage_preservation-1"
            and spoilage.enabled == false and spoilage.level == 1)
          assert(spoilage.unit.count_formula == "50000*1.5^(L-1)" and spoilage.unit.time == 120)
          assert(spoilage.icons[1].icon == "__space-age__/graphics/icons/spoilage.png"
            and spoilage.prerequisites[5] == "space-science-pack"
            and spoilage.prerequisites[6] == "agricultural-science-pack")
          assert(spoilage.effects[1].type == "nothing"
            and spoilage.effects[1].effect_description[2] == "1")

          local expected = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
            "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
            "cryogenic-science-pack"}
          for index, name in ipairs(expected) do
            assert(agriculture.prerequisites[index] == name
              and agriculture.unit.ingredients[index][1] == name
              and agriculture.unit.ingredients[index][2] == 1)
          end
        ''')

    def test_base_stage_leaves_scripted_effect_modules_and_settings_unloaded(self):
        self.lua.execute('''
          -- Historical startup IDs remain target-invariant, but their inactive
          -- Space Age effect/binding bodies still stay unloaded in Base.
          assert(config.spec("ips-enable-research_agricultural_growth_speed") ~= nil)
          assert(config.spec("ips-enable-research_spoilage_preservation") ~= nil)
          local counts = {}; for _, row in ipairs(config.prototypes()) do counts[row.type] = (counts[row.type] or 0) + 1 end
          assert(counts["string-setting"] == 15 and counts["bool-setting"] == 135
            and counts["int-setting"] == 499 and counts["double-setting"] == 240)
          assert(package.loaded["research.settings.space_age_scripted"] == nil)
          assert(package.loaded["compatibility.modern_catalogue.space_age"] == nil)
          assert(package.loaded["compatibility.space_age_scripted_effects"] == nil)
          assert(package.loaded["research.scripted_effects"] == nil)

          local startup, environment = defaults(), full_world({})
          settings, mods, data, helpers, log = {startup = startup}, {}, environment, nil, function() end
          package.preload["compatibility.space_age_scripted_effects"] = function()
            error("base data stage loaded a Space Age binding")
          end
          package.preload["research.scripted_effects"] = function()
            error("base data stage loaded a Space Age technology body")
          end
          package.loaded["overrides.prototype_limits"] = nil
          package.preload["overrides.prototype_limits"] = function()
            error("default data stage loaded prototype limits")
          end
          local ok, message = pcall(dofile, data_final_path)
          package.preload["compatibility.space_age_scripted_effects"] = nil
          package.preload["research.scripted_effects"] = nil
          package.preload["overrides.prototype_limits"] = nil
          assert(ok, message)
          assert(environment.writes == 1 and #environment.emitted == 53)
          assert(package.loaded["compatibility.space_age_scripted_effects"] == nil)
          assert(package.loaded["research.scripted_effects"] == nil)
          assert(package.loaded["overrides.prototype_limits"] == nil)
        ''')

    def test_full_published_setting_output_matches_oracle_without_retired_planner_metadata(self):
        for profile in MODERN_ORACLE["profiles"]:
            active_mods = profile_mods(profile["id"])
            self.lua.globals().profile_setting_mods = lua_table(self.lua, active_mods)
            self.lua.execute('''
              mods = profile_setting_mods
              package.loaded["research.settings"] = nil
              profile_settings = require("research.settings")
            ''')
            actual = {
                row["name"]: plain_lua(row)
                for row in self.lua.eval("profile_settings.prototypes()").values()
            }
            self.assertEqual(actual, intended_setting_rows(profile), profile["id"])

    def test_data_final_full_published_technology_output_matches_oracle(self):
        expected_profiles = {
            profile["id"]: {
                row["name"]: host_row(row["row"])
                for row in profile["published_output"]["data"]["additions"]
                if row["type"] == "technology"
            }
            for profile in MODERN_ORACLE["profiles"]
        }
        patch_profiles = {
            profile["id"]: profile["published_output"]["data"]["patches"]
            for profile in MODERN_ORACLE["profiles"]
        }
        cases = (
            ("base-f210", {}),
            ("space-age-f210", {"space-age": "2.1.23"}),
        )
        for profile, active_mods in cases:
            self.lua.globals().published_mods = lua_table(self.lua, active_mods)
            self.lua.execute('''
              mods = published_mods
              settings, data, helpers, log = {startup = defaults()}, full_world(mods), nil, function() end
              assert(dofile(data_final_path) == nil)
              published_emitted, published_raw = data.emitted, data.raw
            ''')
            actual = {
                row["name"]: plain_lua(row)
                for row in self.lua.globals().published_emitted.values()
            }
            self.assertEqual(actual, expected_profiles[profile], profile)
            expected_patches = patch_profiles[profile]
            self.assertEqual(
                set(self.lua.globals().published_raw.recipe.keys())
                >= {patch["name"] for patch in expected_patches},
                True,
                profile,
            )
            for patch in expected_patches:
                self.assertEqual(patch["changed_paths"], ["allow_productivity"], profile)
                self.assertEqual(
                    plain_lua(self.lua.globals().published_raw.recipe[patch["name"]]),
                    {"allow_productivity": True},
                    f"{profile}:{patch['name']}",
                )

    def test_f200_complete_technology_output_matches_its_own_published_oracle(self):
        oracle = json.loads((ROOT / "spec/mir5/inventory/modern-f200-470.json").read_text(encoding="utf-8"))
        self.lua.execute('''
          local target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"
          target.cargo_research, target.receiver_limits, target.recipe_probability = false, false, "probability"
        ''')
        for profile in oracle["profiles"]:
            active_mods = {"base": "2.0.77"}
            if profile["id"] == "space-age-f200":
                active_mods["space-age"] = "2.0.77"
            self.lua.globals().published_mods = lua_table(self.lua, active_mods)
            self.lua.execute('''
              mods = published_mods
              package.loaded["research.settings"] = nil
              config = require("research.settings")
              settings, data, helpers, log = {startup = defaults()}, full_world(mods), nil, function() end
              assert(dofile(data_final_path) == nil)
            ''')
            expected = {row["name"]: host_row(row["row"])
                        for row in profile["published_output"]["data"]["additions"] if row["type"] == "technology"}
            actual = {row["name"]: plain_lua(row) for row in self.lua.globals().data.emitted.values()}
            self.assertEqual(actual, expected, profile["id"])

    def test_effective_global_option_lazily_activates_prototype_limits(self):
        self.lua.execute('''
          local startup, environment = defaults(), full_world({})
          startup["mir-prototype-positive-power-floor"].value = true
          environment.raw["fixture-receiver"] = {zero = {energy_usage = "0W"}}
          settings, mods, data, helpers, log = {startup = startup}, {}, environment, nil, function() end
          package.loaded["overrides.prototype_limits"] = nil
          assert(dofile(data_final_path) == nil)
          assert(environment.writes == 1 and #environment.emitted == 53)
          assert(package.loaded["overrides.prototype_limits"] ~= nil)
          assert(environment.raw["fixture-receiver"].zero.energy_usage == "1W")
        ''')

    def test_space_age_data_stage_installs_the_two_authored_effect_rows_once(self):
        self.lua.execute('''
          mods = {['space-age'] = '2.1.23'}
          package.loaded["research.settings"] = nil
          package.loaded["research.settings.space_age_scripted"] = nil
          local space_config = require("research.settings")
          local startup = {}
          for _, spec in ipairs(space_config.prototypes()) do startup[spec.name] = {value = spec.default_value} end
          local environment = full_world(mods)
          settings, data, helpers, log = {startup = startup}, environment, nil, function() end
          assert(dofile(data_final_path) == nil)
          assert(environment.writes == 1 and #environment.emitted == 71)
          local ids = {}
          for _, row in ipairs(environment.emitted) do ids[row.name] = row end
          assert(ids["recipe-prod-research_gears-1"] ~= nil)
          assert(ids["recipe-prod-research_agricultural_growth_speed-1"] ~= nil)
          assert(ids["recipe-prod-research_spoilage_preservation-1"] ~= nil)
          assert(ids["braking-force-8"] ~= nil and ids["worker-robots-storage-4"] ~= nil)
        ''')

    def test_k2so_scripted_binding_keeps_the_captured_spoilage_subset_and_lazy_profiles(self):
        self.lua.execute('''
          local selector = require("compatibility.space_age_scripted_effects")
          local space_age = "compatibility.space_age_scripted_effects.space_age"
          local k2so_body = "compatibility.space_age_scripted_effects.k2so"
          local names = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
            "production-science-pack", "space-science-pack", "agricultural-science-pack",
            "electromagnetic-science-pack", "cryogenic-science-pack"}
          local science = {}
          for _, name in ipairs(names) do science[name] = {} end
          local raw = {technology = science, tool = science, item = {spoilage = {}}}
          local k2 = {['space-age'] = '2.1.23', Krastorio2 = '2.1.4',
            ['Krastorio2-spaced-out'] = '2.0.19', Krastorio2Assets = '2.1.0',
            ['k2so-assets'] = '1.0.7'}

          package.loaded[space_age], package.loaded[k2so_body] = nil, nil
          package.preload[space_age] = function() error("inactive Space Age profile was loaded") end
          local bindings = selector.select(k2, raw)
          assert(package.loaded[space_age] == nil, "K2SO selection loaded the inactive Space Age body")
          assert(#bindings.agriculture.prerequisites == 7 and #bindings.spoilage.prerequisites == 4)
          local expected = {"production-science-pack", "space-science-pack",
            "agricultural-science-pack", "cryogenic-science-pack"}
          for index, name in ipairs(expected) do
            assert(bindings.spoilage.prerequisites[index] == name
              and bindings.spoilage.ingredients[index][1] == name
              and bindings.spoilage.ingredients[index][2] == 1)
          end
          package.preload[space_age] = nil

          local partial = {['space-age'] = '2.1.23', Krastorio2 = '2.1.4'}
          assert(not pcall(selector.select, partial, raw), "partial K2SO selected a fallback profile")

          -- Incidental asset-only dependencies do not activate an overhaul
          -- or load its binding body in an otherwise ordinary Space Age game.
          package.loaded[k2so_body] = nil
          package.preload[k2so_body] = function() error("inactive K2SO profile was loaded") end
          local ordinary = selector.select({['space-age'] = '2.1.23',
            Krastorio2Assets = '2.1.0', ['k2so-assets'] = '1.0.7'}, raw)
          assert(#ordinary.spoilage.prerequisites == 7 and package.loaded[k2so_body] == nil)
          package.preload[k2so_body] = nil
        ''')

    def test_valid_family_forward_reference_and_one_write(self):
        self.lua.execute('''
          local a, b = build(), build(); a.name = "alpha-1"; b.name = "beta-1"
          a.prerequisites = {"beta-1"}; b.prerequisites = {}
          local environment = world(); generator.install({a, b}, environment)
          assert(environment.writes == 1 and environment.emitted[1].name == "alpha-1")
        ''')

    def test_all_family_failures_precede_first_write(self):
        self.lua.execute('''
          local a, b = build(), build(); b.name = "second-1"; b.effects[1].recipe = "missing"
          refused({a,b}, world(), "missing recipe")
          b = build(); refused({a,b}, world(), "duplicate")
          local environment = world(); environment.raw.technology[a.name] = {}
          refused({a}, environment, "duplicate")
          b.name = "second-1"; a.prerequisites = {b.name}; b.prerequisites = {a.name}
          refused({a,b}, world(), "cycle")
          a = build(); a.unit.ingredients[1][1] = "missing"; refused({a}, world(), "ingredient")
          a = build(); a.effects[1].change = 0/0; refused({a}, world(), "productivity")
          refused({[1]=build(),[3]=build()}, world(), "missing entry")
        ''')

    def test_item_science_is_not_limited_to_tools(self):
        self.lua.execute('''
          local environment = world(); environment.raw.item = environment.raw.tool; environment.raw.tool = {}
          generator.install({build()}, environment); assert(environment.writes == 1)
        ''')

    def test_unrelated_world_growth_is_not_traversed(self):
        self.lua.execute('''
          local environment = world()
          environment.raw.fluid = setmetatable({}, {__pairs=function() error("unrelated world scan") end})
          environment.raw.recipe = setmetatable(environment.raw.recipe, {__pairs=function() error("whole recipe scan") end})
          generator.install({build()}, environment); assert(environment.writes == 1)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(GeneratorTests))
    if args.output:
        paths = sorted((ROOT / "source/mir5").rglob("*.lua")) + [Path(__file__).resolve()]
        record = {"kind": "mir5-gear-host-controls-not-native-evidence", "status": "passed" if result.wasSuccessful() else "failed",
                  "tests": result.testsRun, "failures": len(result.failures), "errors": len(result.errors), "lua": "5.2",
                  "inputs": [{"path": p.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths]}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    sys.exit(0 if result.wasSuccessful() else 1)

"""Explicit data-stage Lua worlds; assertions and frozen expectations stay with tests."""
from pathlib import Path


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


def build_generator_world(runtime_factory, *, source_root, science_sources, material_native):
    """Construct the existing bounded world from explicit caller-owned inputs."""
    source_root = Path(source_root)
    lua = runtime_factory(unpack_returned_tuples=True)
    lua.globals().player_root = source_root.as_posix()
    lua.execute('''
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
          local function source_copy(value)
            if type(value) ~= "table" then return value end
            local out = {}; for key, child in pairs(value) do out[key] = source_copy(child) end
            return out
          end
          function full_world(active_mods, before_data_stage)
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
            local profile = active_mods and active_mods["space-age"] and "space-age-f210" or "base-f210"
            local sources = source_worlds[profile].raw
            for name, row in pairs(sources.recipe) do recipes[name] = source_copy(row) end
            for name, row in pairs(sources.technology) do technologies[name] = source_copy(row) end
            -- The K2SO host fixture is a named subset from the current
            -- no-MIR capture. It supplies only the four recipes and four
            -- owner effects that the restored material rows bind directly.
            if modern_catalogue.is_k2so(active_mods) then
              for name, row in pairs(k2so_material_native.recipe) do recipes[name] = source_copy(row) end
              for name, row in pairs(k2so_material_native.technology) do technologies[name] = source_copy(row) end
            end
            local lab_inputs = {}
            for name in pairs(tools) do lab_inputs[#lab_inputs + 1] = name end
            table.sort(lab_inputs)
            local items = source_copy(sources.item); items.spoilage = {}
            for name, recipe in pairs(recipes) do
              if recipe.type == nil then recipe.type = "recipe" end
              if recipe.name == nil then recipe.name = name end
            end
            -- Most controls enter directly at final-fixes. Supply data.lua's
            -- prior private transport, without counting it as Generator
            -- publication. Real data-stage controls request a pre-data world.
            local private
            if before_data_stage ~= true then
              private = {["more-infinite-research-native-adoptions"]={type="mod-data",
                name="more-infinite-research-native-adoptions",data={schema=1,owners={},withheld={},credits={}}}}
            end
            return {raw = {technology = technologies, tool = tools, item = items, recipe = recipes,
              ["mod-data"] = private,
              ["ammo-category"] = {["cannon-shell"] = {}},
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
    lua.globals().data_final_path = (source_root / "data-final-fixes.lua").as_posix()
    lua.globals().source_worlds = lua_table(lua, science_sources)
    lua.globals().k2so_material_native = lua_table(lua, material_native)
    return lua

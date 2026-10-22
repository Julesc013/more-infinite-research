"""Pure Lua 5.2 controls for the bounded MIR 5 Library model, not native GUI evidence."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LibraryModelTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          catalogue = require("research.catalogue")
          model = require("presentation.library_model")

          function technology(name, options)
            options = options or {}
            local prerequisite = options.prerequisites or {automation = {name = "automation", researched = true}}
            local effects = options.effects or {{type = "change-recipe-productivity", recipe = "iron-gear-wheel", change = .1}}
            return {
              name = name,
              level = options.level or 1,
              researched = options.researched == true,
              enabled = options.enabled ~= false,
              visible_when_disabled = options.visible_when_disabled == true,
              order = options.order or "p[research_gears]",
              prerequisites = prerequisite,
              prototype = {max_level = options.max_level or 4294967295, effects = effects},
              research_unit_count = options.count or 8000,
              research_unit_count_formula = options.count_formula,
              research_unit_energy = options.energy or 60,
              research_unit_ingredients = options.ingredients or {
                {name = "automation-science-pack", amount = 1},
                {name = "logistic-science-pack", amount = 1}
              }
            }
          end
        ''')

    def test_catalogue_is_current_gear_metadata_and_detached(self):
        self.lua.execute('''
          local first, second = catalogue.declared(), catalogue.declared()
          assert(#first == 1 and first[1].id == "recipe-prod-research_gears-1")
          assert(first[1].family == "mir" and first[1].recipe == "iron-gear-wheel")
          assert(first[1].cap_setting == "ips-max-level-research_gears")
          assert(#first[1].settings == 7 and first[1].settings[1] == "ips-enable-research_gears")
          first[1].settings[1] = "foreign"; first[1].id = "foreign"
          assert(second[1].id == "recipe-prod-research_gears-1"
            and second[1].settings[1] == "ips-enable-research_gears")
        ''')

    def test_normalize_preserves_schema_three_defaults_and_copies_view(self):
        self.lua.execute('''
          local hidden = {["recipe-prod-research_gears-1"] = true}
          local view = model.normalize({mode = 9, status = 0, page = 0,
            search = "  Iron_Gear-Wheel  ", family = "unknown", sort = "other",
            hidden = hidden, selected = "recipe-prod-research_gears-1"})
          assert(view.schema == 3 and view.mode == 1 and view.status == 1 and view.page == 1)
          assert(view.family == "mir" and view.sort == "progression" and view.stable_sort == "progression")
          assert(view.search == "iron gear wheel" and view.tab == "research" and view.settings_scope == "research")
          assert(view.hidden["recipe-prod-research_gears-1"] and view.selected == "recipe-prod-research_gears-1")
          hidden["recipe-prod-research_gears-1"] = false
          assert(view.hidden["recipe-prod-research_gears-1"])
        ''')

    def test_default_mir_view_does_not_enumerate_foreign_catalogue(self):
        self.lua.execute('''
          local id = "recipe-prod-research_gears-1"
          local gear = technology(id, {level = 10})
          local unrelated = technology("foreign-unrelated", {order = "a[foreign]"})
          local technologies = setmetatable({[id] = gear, [unrelated.name] = unrelated}, {
            __pairs = function() error("default MIR view enumerated native catalogue") end
          })
          local force = {
            technologies = technologies, research_queue = {gear, unrelated, gear}, current_research = gear
          }
          local rows = model.rows(force, catalogue.declared(), {}, {[id] = "Iron Gear Wheel Productivity"})
          assert(#rows == 1)
          local row = rows[1]
          assert(row.id == id and row.name == "Iron Gear Wheel Productivity" and row.family == "mir")
          assert(row.current_level == 10 and row.completed_count == nil)
          assert(row.cap == nil and row.cap_state == "unavailable" and row.finite == false and row.status == "queued")
          assert(row.queued_count == 2 and row.queue_index == 1 and row.current and row.ready)
          assert(#row.prerequisites == 1 and row.prerequisites[1] == "automation")
          assert(unrelated.order == "a[foreign]" and gear.level == 10)
        ''')

    def test_explicit_external_and_all_views_scan_once_and_sort_deterministically(self):
        self.lua.execute('''
          local id = "recipe-prod-research_gears-1"
          local gear = technology(id, {order = "p[gear]"})
          local alpha = technology("alpha-external", {order = "a[same]"})
          local beta = technology("beta-external", {order = "a[same]"})
          local scans = 0
          local raw = {[id] = gear, [alpha.name] = alpha, [beta.name] = beta}
          local force = {technologies = setmetatable(raw, {
            __pairs = function(value) scans = scans + 1; return next, value, nil end
          }), research_queue = {}}
          local external = model.rows(force, catalogue.declared(), {family = "external", sort = "native"}, {})
          assert(scans == 1 and #external == 2 and external[1].id == alpha.name and external[2].id == beta.name)
          local all = model.rows(force, catalogue.declared(), {family = "all", sort = "name-desc"}, {
            [id] = "Gear", [alpha.name] = "Alpha", [beta.name] = "Beta"
          })
          assert(scans == 2 and #all == 3 and all[1].id == id and all[2].id == beta.name and all[3].id == alpha.name)
        ''')

    def test_search_filters_modes_status_and_hidden_entries(self):
        self.lua.execute('''
          local id = "recipe-prod-research_gears-1"
          local gear = technology(id, {level = 3})
          local force = {technologies = {[id] = gear}, research_queue = {}}
          local translated = {[id] = "Iron Gear Wheel Productivity"}
          assert(#model.rows(force, catalogue.declared(), {search = "iron_gear", mode = 3, status = 2}, translated) == 1)
          assert(#model.rows(force, catalogue.declared(), {mode = 2}, translated) == 0)
          assert(#model.rows(force, catalogue.declared(), {hidden = {[id] = true}}, translated) == 0)
          local hidden = model.rows(force, catalogue.declared(), {
            hidden = {[id] = true}, visibility = 2
          }, translated)
          assert(#hidden == 1 and hidden[1].hidden and hidden[1].status == "ready")
        ''')

    def test_selected_detail_is_bounded_and_never_reuses_native_tables(self):
        self.lua.execute('''
          local id = "recipe-prod-research_gears-1"
          local effects, ingredients = {}, {}
          for index = 1, 17 do
            effects[index] = {type = "change-recipe-productivity", recipe = "recipe-" .. index, change = .1}
            ingredients[index] = {name = "pack-" .. index, amount = index}
          end
          local gear = technology(id, {effects = effects, ingredients = ingredients, count_formula = "100*L"})
          local force = {technologies = setmetatable({[id] = gear}, {
            __pairs = function() error("detail scanned full native catalogue") end
          }), research_queue = {}}
          local detail = assert(model.detail(force, catalogue.declared(), {selected = id}, {[id] = "Gears"}))
          assert(detail.name == "Gears" and #detail.effects == 16 and not detail.effects_complete)
          assert(#detail.cost.ingredients == 16 and not detail.ingredients_complete and detail.cost.count_formula == "100*L")
          detail.effects[1].recipe = "mutated"; detail.cost.ingredients[1].name = "mutated"
          assert(effects[1].recipe == "recipe-1" and ingredients[1].name == "pack-1")
        ''')

    def test_native_style_proxies_reject_unsupported_member_reads(self):
        self.lua.execute('''
          local reads = {}
          local function hostile(fields, label)
            return setmetatable({}, {
              __index = function(_, key)
                local value = fields[key]
                if value ~= nil then return value end
                reads[#reads + 1] = label .. "." .. tostring(key)
                error(label .. " unknown member " .. tostring(key))
              end,
              __newindex = function() error(label .. " write") end
            })
          end
          local id = "recipe-prod-research_gears-1"
          local ingredient = hostile({name = "automation-science-pack", amount = 1}, "ResearchIngredient")
          local effect = hostile({type = "change-recipe-productivity", recipe = "iron-gear-wheel", change = .1}, "TechnologyModifier")
          local prerequisite = hostile({name = "automation", researched = true}, "LuaTechnology prerequisite")
          local prototype = hostile({max_level = 4294967295, effects = {effect}}, "LuaTechnologyPrototype")
          local gear = hostile({
            name = id, level = 6, researched = false, enabled = true,
            visible_when_disabled = false, order = "p[research_gears]",
            prerequisites = {automation = prerequisite}, prototype = prototype,
            research_unit_count = 8000, research_unit_count_formula = "100*L",
            research_unit_energy = 60, research_unit_ingredients = {ingredient}
          }, "LuaTechnology")
          local force = hostile({
            technologies = {[id] = gear}, research_queue = {id}, current_research = gear
          }, "LuaForce")
          local context = {cap_provider = function(actual_force)
            assert(actual_force == force)
            return {[id] = 10}
          end}
          local rows = model.rows(force, catalogue.declared(), {}, {[id] = "Gears"}, context)
          assert(#rows == 1 and rows[1].current_level == 6 and rows[1].queued_count == 1)
          assert(rows[1].completed_count == nil and rows[1].cap == 10 and rows[1].cap_state == "finite")
          local detail = assert(model.detail(force, catalogue.declared(), {selected = id}, {}, context))
          assert(detail.cost.ingredients[1].name == "automation-science-pack")
          assert(detail.effects[1].recipe == "iron-gear-wheel" and detail.effects[1].change == .1)
          assert(#reads == 0, table.concat(reads, ", "))
        ''')

    def test_model_does_not_import_generator_or_touch_host_globals(self):
        source = (ROOT / "source/mir5/presentation/library_model.lua").read_text(encoding="utf-8")
        catalogue = (ROOT / "source/mir5/research/catalogue.lua").read_text(encoding="utf-8")
        self.assertNotIn("require(", source)
        self.assertNotIn("Generator", source)
        self.assertNotIn("require(", catalogue)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LibraryModelTests))
    sys.exit(0 if result.wasSuccessful() else 1)

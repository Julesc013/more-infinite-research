"""Pure Lua 5.2 controls for the bounded MIR 5 Library model, not native GUI evidence."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LibraryModelTests(unittest.TestCase):
    def test_data_stage_identity_lookup_does_not_select_a_runtime_catalogue(self):
        self.lua.execute('''
          script, mods = nil, {}
          package.loaded["research.catalogue"] = nil
          local modern = require("compatibility.modern_catalogue")
          modern.select = function() error("data identity lookup selected runtime metadata") end
          local catalogue = require("research.catalogue")
          assert(catalogue.gear_id() == "recipe-prod-research_gears-1")
        ''')

    def test_real_catalogue_queries_need_no_imports_or_reselection_after_control_parse(self):
        editions = json.loads((ROOT / "targets/editions.json").read_text())["targets"]
        profiles = [
            "library-multiplayer-f200-2077", "library-native-f210", "space-age-f210-2123",
            "k2-base-f200-2077", "k2so-f210-2123", "bob-angel-f200-2077",
            "bob-core-f210-2123", "py-coal-f200-2077",
            "py-alienlife-hightech-f200-2077", "armor-bobwarfare-f200-2077",
            "atan-base-f200-2077", "atan-space-age-f200-2077",
        ]
        for name in profiles:
            with self.subTest(profile=name):
                profile = json.loads((ROOT / f"tests/profiles/{name}.json").read_text())
                lua = LuaRuntime(unpack_returned_tuples=True)
                lua.globals().player_root = (ROOT / "source").as_posix()
                target_id = "f210" if name == "library-native-f210" else profile["target"]
                target = lua.table_from(editions[target_id])
                target["id"] = target_id
                lua.globals().selected_target = target
                lua.globals().selected_mods = lua.table_from({
                    mod["name"]: mod["version"] for mod in profile["mods"] if mod["enabled"]
                })
                lua.execute('''
                  package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
                  package.loaded["platform.target"] = selected_target
                  script, mods = {active_mods=selected_mods}, selected_mods
                  local modern = require("compatibility.modern_catalogue")
                  local select, selections = modern.select, 0
                  modern.select = function(...)
                    selections = selections + 1
                    return select(...)
                  end
                  local catalogue = require("research.catalogue")
                  local parse_selections = selections
                  -- Factorio refuses even cached require calls in callbacks.
                  require = function(name) error("late runtime import: " .. name) end
                  local first, second = catalogue.declared(), catalogue.declared()
                  assert(parse_selections == 1 and selections == parse_selections,
                    "runtime query rebuilt the authored profile")
                  assert(#first > 1 and #first == #second)
                  assert(first[1].id == "recipe-prod-research_gears-1")
                  first[1].id, first[1].settings[1] = "foreign", "foreign"
                  local third = catalogue.declared()
                  assert(second[1].id == "recipe-prod-research_gears-1"
                    and third[1].id == second[1].id
                    and third[1].settings[1] == "ips-enable-research_gears")
                  assert(package.loaded["research.generator"] == nil)
                ''')

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
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

    def test_catalogue_is_complete_base_metadata_and_detached(self):
        self.lua.execute('''
          local first, second = catalogue.declared(), catalogue.declared()
          local first_by_id, second_by_id = {}, {}
          local families = {}
          for _, row in ipairs(first) do first_by_id[row.id], families[row.family] = row, true end
          for _, row in ipairs(second) do second_by_id[row.id] = row end
          local gear = first_by_id["recipe-prod-research_gears-1"]
          local science = first_by_id["recipe-prod-research_science_pack_productivity-1"]
          assert(#first == 54 and gear and gear.family == "research_gears" and gear.recipe == "iron-gear-wheel")
          assert(families.research_gears and families["braking-force"])
          assert(first_by_id["braking-force-8"].cap_setting == "mir-max-level-braking-force")
          assert(not families.research_agricultural_growth_speed and not families.research_spoilage_preservation)
          assert(gear.cap_setting == "ips-max-level-research_gears")
          assert(#gear.settings == 7 and gear.settings[1] == "ips-enable-research_gears")
          assert(science and science.family == "research_science_pack_productivity"
            and science.setting == "ips-enable-research_science_pack_productivity"
            and science.cap_setting == "ips-max-level-research_science_pack_productivity"
            and #science.settings == 7)
          gear.settings[1] = "foreign"; gear.id = "foreign"
          assert(second_by_id["recipe-prod-research_gears-1"]
            and second_by_id["recipe-prod-research_gears-1"].settings[1] == "ips-enable-research_gears")
        ''')

    def test_availability_is_small_authored_detached_and_checks_only_the_named_lab_owner(self):
        self.lua.execute('''
          local availability = require("presentation.availability")

          local productivity_target = {recipe_productivity = true}
          local base = availability.rows({}, productivity_target, nil, "")
          assert(#base == 2
            and base[1].family == "research_agricultural_growth_speed"
            and base[2].family == "research_spoilage_preservation")
          assert(base[1].status == "not-added" and base[1].reason == "requires-space-age"
            and base[1].required_mod == "space-age" and base[1].technology_id == nil)
          base[1].family, base[1].required_mod = "foreign", "foreign"
          local fresh = availability.rows({}, productivity_target, nil, "")
          assert(fresh[1].family == "research_agricultural_growth_speed"
            and fresh[1].required_mod == "space-age")
          local spoilage = availability.rows({}, productivity_target, nil, "spoilage-preservation")
          assert(#spoilage == 1 and spoilage[1].family == "research_spoilage_preservation")

          local product = {valid = true, prototype = {effects = {
            {type = "laboratory-productivity", modifier = .10000000149}
          }}}
          local force = {
            technologies = setmetatable({["research-productivity"] = product}, {
              __pairs = function() error("availability scanned native technologies") end
            })
          }
          local space_age = { ["space-age"] = "2.1.23" }
          local native = availability.rows(space_age, productivity_target, force, "lab")
          assert(#native == 1 and native[1].family == "research_lab_productivity"
            and native[1].reason == "native-research-productivity"
            and native[1].native_owner == "research-productivity"
            and native[1].technology_id == nil)
          assert(#availability.rows(space_age, productivity_target, force, "spoilage") == 0,
            "active Space Age must not report its two absent-DLC explanations")

          assert(#availability.rows({}, {recipe_productivity = false}, force, "") == 0,
            "historical targets without recipe productivity must not advertise modern omissions")

          product.prototype.effects[1].modifier = .1001
          assert(#availability.rows(space_age, productivity_target, force, "") == 0,
            "a changed named native effect must not invent the laboratory explanation")
          product.prototype.effects = {{type = "laboratory-productivity", modifier = .1}, {type = "other", modifier = .1}}
          assert(#availability.rows(space_age, productivity_target, force, "") == 0,
            "the captured owner contract has exactly one effect")
          force.technologies["research-productivity"] = nil
          assert(#availability.rows(space_age, productivity_target, force, "") == 0,
            "an absent named owner must not be inferred from the wider technology set")
          force.technologies["research-productivity"] = setmetatable({}, {
            __index = function() error("malformed named owner") end
          })
          assert(#availability.rows(space_age, productivity_target, force, "") == 0,
            "a malformed named owner must not escape the bounded availability check")
        ''')

    def test_availability_binds_withheld_materials_to_exact_bob_closures_without_force_mutation(self):
        self.lua.execute('''
          local availability = require("presentation.availability")

          local function locked_force(technologies)
            setmetatable(technologies, {
              __pairs = function() error("availability scanned native technologies") end,
              __newindex = function() error("availability mutated native technologies") end,
            })
            return {technologies = technologies}
          end

          local f200 = {id = "f200", factorio_version = "2.0", minimum_base = "2.0.77", recipe_productivity = true}
          local bob_angel = {
            base = "2.0.77", angelsbioprocessing = true, angelsbioprocessinggraphics = true,
            angelspetrochem = true, angelspetrochemgraphics = true, angelsrefining = true,
            angelsrefininggraphics = true, angelssmelting = true, angelssmeltinggraphics = true,
            bobelectronics = true, boblibrary = true, bobores = true, bobplates = true, bobrevamp = true,
          }
          local empty_force = locked_force({})
          local enabled_streams = {research_material_lead = {enabled = true}}
          local f200_rows = availability.rows(bob_angel, f200, empty_force, "material", enabled_streams)
          assert(#f200_rows == 11 and f200_rows[1].family == "research_material_lead"
            and f200_rows[1].reason == "not-available-in-bob-angel-profile")
          assert(f200_rows[1].emitted_id == nil,
            "availability must return detached player descriptors")
          f200_rows[1].family = "foreign"
          assert(availability.rows(bob_angel, f200, empty_force, "lead", enabled_streams)[1].family == "research_material_lead")

          bob_angel.bobrevamp = nil
          assert(#availability.rows(bob_angel, f200, empty_force, "material", enabled_streams) == 0,
            "an incomplete Bob/Angel closure must not advertise these material explanations")
          bob_angel.bobrevamp = true
          bob_angel["space-age"] = "2.1.23"
          assert(#availability.rows(bob_angel, f200, empty_force, "lead", enabled_streams) == 0,
            "a mixed Bob/Angel closure must not inherit the captured F200 explanation")
          bob_angel["space-age"] = nil

          local present_force = locked_force({["recipe-prod-research_material_lead-1"] = {valid = true}})
          assert(#availability.rows(bob_angel, f200, present_force, "lead", enabled_streams) == 0,
            "a real exact technology must suppress its terminal explanation")
          settings = {startup = { ["ips-enable-research_material_lead"] = {value = false} }}
          assert(#availability.rows(bob_angel, f200, empty_force, "lead", enabled_streams) == 1,
            "Availability must use the supplied effective stream, not a raw setting")
          local disabled_streams = {research_material_lead = {enabled = false}}
          settings.startup["ips-enable-research_material_lead"].value = true
          assert(#availability.rows(bob_angel, f200, empty_force, "lead", disabled_streams) == 0,
            "an effective disabled stream must not receive an omission explanation")

          local f210 = {id = "f210", factorio_version = "2.1", minimum_base = "2.1.23", recipe_productivity = true}
          local bobtech_angel = {
            base = "2.1.23", ["space-age"] = "2.1.23", boblibrary = true, bobores = true,
            bobplates = true, bobelectronics = true, bobtech = true, angelsrefining = true,
            angelsrefininggraphics = true, angelspetrochem = true, angelspetrochemgraphics = true,
            angelssmelting = true, angelssmeltinggraphics = true,
          }
          local f210_rows = availability.rows(bobtech_angel, f210, empty_force, "lead", enabled_streams)
          assert(#f210_rows == 1 and f210_rows[1].family == "research_material_lead"
            and f210_rows[1].reason == "not-available-in-bobtech-angel-profile")
          assert(#availability.rows(bobtech_angel, f210, empty_force, "zinc", enabled_streams) == 0,
            "the F210 explanation list must not invent a family outside its captured withholding")
          f210.minimum_base = "2.1.24"
          assert(#availability.rows(bobtech_angel, f210, empty_force, "lead", enabled_streams) == 0,
            "a different F210 target record must not reuse this closure")
          f210.minimum_base = "2.1.23"
          bobtech_angel.Krastorio2 = true
          assert(#availability.rows(bobtech_angel, f210, empty_force, "lead", enabled_streams) == 0,
            "an excluded mixed closure must not reuse the BobTech explanation")
          bobtech_angel.Krastorio2 = nil

          assert(next(empty_force.technologies) == nil and present_force.technologies["recipe-prod-research_material_lead-1"] ~= nil,
            "availability must not mutate the force or named technologies")
        ''')

    def test_normalize_preserves_schema_three_defaults_and_copies_view(self):
        self.lua.execute('''
          local hidden = {["recipe-prod-research_gears-1"] = true}
          local view = model.normalize({mode = 9, status = 0, page = 0,
            search = "  Iron_Gear-Wheel  ", family = "research_gears", sort = "other",
            hidden = hidden, selected = "recipe-prod-research_gears-1"})
          assert(view.schema == 3 and view.mode == 1 and view.status == 1 and view.page == 1)
          assert(view.family == "research_gears" and view.sort == "progression" and view.stable_sort == "progression")
          assert(view.search == "iron gear wheel" and view.tab == "research" and view.settings_scope == "research")
          assert(view.hidden["recipe-prod-research_gears-1"] and view.selected == "recipe-prod-research_gears-1")
          hidden["recipe-prod-research_gears-1"] = false
          assert(view.hidden["recipe-prod-research_gears-1"])
          assert(model.normalize({family = "unlisted-authored-family"}).family == "unlisted-authored-family")
          assert(model.normalize({family = string.rep("x", 161)}).family == "mir")
          local availability = model.normalize({tab = "availability", visibility = 3})
          assert(availability.tab == "research" and availability.visibility == 3)
        ''')

    def test_normalize_keeps_bounded_historical_page_and_sort_state(self):
        self.lua.execute('''
          local normalized = model.normalize({page = 30000, sort = "name-desc",
            stable_sort = "native", hidden = {"recipe-prod-research_gears-1"}})
          assert(normalized.page == 30000 and normalized.sort == "name-desc"
            and normalized.stable_sort == "native"
            and normalized.hidden["recipe-prod-research_gears-1"])
          assert(model.normalize({page = 30001}).page == 1)
        ''')

    def test_retained_page_never_slices_or_reorders_the_continuous_library_rows(self):
        self.lua.execute('''
          local technologies = {}
          for index = 1, 25 do
            local id = string.format("page-continuity-%02d", index)
            technologies[id] = technology(id, {order = string.format("p[%02d]", index)})
          end
          local force = {technologies = technologies, research_queue = {}}
          local function ids(page)
            local rows = model.rows(force, {}, {family = "all", sort = "native", page = page}, {})
            local result = {}
            for index, row in ipairs(rows) do result[index] = row.id end
            return table.concat(result, ",")
          end
          local first = ids(1)
          assert(#model.rows(force, {}, {family = "all", sort = "native", page = 1}, {}) == 25)
          assert(ids(2) == first and ids(30000) == first)
          assert(first == "page-continuity-01,page-continuity-02,page-continuity-03,page-continuity-04,page-continuity-05,page-continuity-06,page-continuity-07,page-continuity-08,page-continuity-09,page-continuity-10,page-continuity-11,page-continuity-12,page-continuity-13,page-continuity-14,page-continuity-15,page-continuity-16,page-continuity-17,page-continuity-18,page-continuity-19,page-continuity-20,page-continuity-21,page-continuity-22,page-continuity-23,page-continuity-24,page-continuity-25")
        ''')

    def test_hidden_input_budget_counts_visited_entries_including_rejected_values(self):
        self.lua.execute('''
          local visits = 0
          local hostile = setmetatable({}, {
            __pairs = function()
              local index = 0
              return function()
                index, visits = index + 1, visits + 1
                if visits > 129 then error("hidden input was scanned past its visit budget") end
                if index <= 200 then return "invalid-hidden-" .. index, false end
              end
            end
          })
          local normalized = model.normalize({hidden = hostile})
          -- `pairs` makes one final iterator call to observe termination;
          -- exactly 128 hostile entries were inspected.
          assert(next(normalized.hidden) == nil and visits == 129)
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
          local rows = model.rows(force, {{id = id, family = "research_gears"}}, {}, {[id] = "Iron Gear Wheel Productivity"})
          assert(#rows == 1)
          local row = rows[1]
          assert(row.id == id and row.name == "Iron Gear Wheel Productivity" and row.family == "research_gears")
          assert(row.current_level == 10 and row.completed_count == nil)
          assert(row.cap == nil and row.cap_state == "unavailable" and row.finite == false and row.status == "queued")
          assert(row.queued_count == 2 and row.queue_index == 1 and row.current and row.ready)
          assert(#row.prerequisites == 1 and row.prerequisites[1] == "automation")
          assert(unrelated.order == "a[foreign]" and gear.level == 10)
        ''')

    def test_authored_family_descriptor_filters_declared_rows_without_native_discovery(self):
        self.lua.execute('''
          local id = "recipe-prod-research_gears-1"
          local gear = technology(id, {level = 3})
          local force = {technologies = setmetatable({[id] = gear}, {
            __pairs = function() error("authored family enumerated native catalogue") end
          }), research_queue = {}}
          local declared = {{id = id, family = "research_gears", progression = 1}}
          local rows = model.rows(force, declared, {family = "research_gears"}, {})
          assert(#rows == 1 and rows[1].id == id and rows[1].family == "research_gears")
          assert(#model.rows(force, declared, {family = "unknown-family"}, {}) == 0)
        ''')

    def test_absent_declared_technology_is_not_a_library_row_or_availability_placeholder(self):
        self.lua.execute('''
          local present_id = "recipe-prod-research_gears-1"
          local absent_id = "agricultural-growth-speed"
          local present = technology(present_id, {level = 3})
          local force = {technologies = {[present_id] = present}, research_queue = {}}
          local declared = {
            {id = present_id, family = "research_gears", progression = 1},
            {id = absent_id, family = "research_agricultural_growth_speed", progression = 2}
          }
          local normal = model.rows(force, declared, {family = "mir"}, {})
          local absent_family = model.rows(force, declared, {
            family = "research_agricultural_growth_speed",
            hidden = {[absent_id] = true},
            visibility = 2
          }, {})
          assert(#normal == 1 and normal[1].id == present_id)
          assert(#absent_family == 0)
          local detail, reason = model.detail(force, declared, {selected = absent_id}, {})
          assert(detail == nil and reason == "technology_not_found")
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

    def test_name_sort_is_strict_for_both_directions_and_casefold_ties(self):
        self.lua.execute('''
          local labels = {
            ["alpha-a"] = "ALPHA", ["alpha-b"] = "alpha", ["bravo"] = "Bravo",
            ["charlie"] = "Charlie", ["delta"] = "Delta"
          }
          local function observed(insertion, sort)
            local technologies = {}
            for _, id in ipairs(insertion) do
              technologies[id] = technology(id, {order = "z[unrelated]"})
            end
            local rows = model.rows({technologies = technologies, research_queue = {}}, {}, {
              family = "all", sort = sort
            }, labels)
            local ids = {}
            for index, row in ipairs(rows) do ids[index] = row.id end
            return table.concat(ids, ",")
          end
          local forward = {"alpha-a", "alpha-b", "bravo", "charlie", "delta"}
          local reverse = {"delta", "charlie", "bravo", "alpha-b", "alpha-a"}
          local asc = "alpha-a,alpha-b,bravo,charlie,delta"
          local desc = "delta,charlie,bravo,alpha-a,alpha-b"
          assert(observed(forward, "name-asc") == asc and observed(reverse, "name-asc") == asc)
          assert(observed(forward, "name-desc") == desc and observed(reverse, "name-desc") == desc)
        ''')

    def test_search_filters_modes_status_and_hidden_entries(self):
        self.lua.execute('''
          local id = "recipe-prod-research_gears-1"
          local gear = technology(id, {level = 3})
          local force = {technologies = {[id] = gear}, research_queue = {}}
          local translated = {[id] = "Iron Gear Wheel Productivity"}
          local declared = {{id = id, family = "research_gears"}}
          assert(#model.rows(force, declared, {search = "iron_gear", mode = 3, status = 2}, translated) == 1)
          assert(#model.rows(force, declared, {mode = 2}, translated) == 0)
          assert(#model.rows(force, declared, {hidden = {[id] = true}}, translated) == 0)
          local hidden = model.rows(force, declared, {
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

    def test_selected_detail_keeps_named_native_modifier_fields_without_catalogue_scan(self):
        self.lua.execute('''
          local id = "weapon-shooting-speed-7"
          local weapon = technology(id, {effects = {
            {type = "gun-speed", ammo_category = "bullet", modifier = .2},
            {type = "worker-robot-storage", modifier = 1}
          }})
          local force = {technologies = setmetatable({[id] = weapon}, {
            __pairs = function() error("detail scanned native catalogue") end
          }), research_queue = {}}
          local detail = assert(model.detail(force, {{id = id, family = "weapon-shooting-speed"}}, {selected = id}, {}))
          assert(detail.effects[1].type == "gun-speed" and detail.effects[1].modifier == .2
            and detail.effects[1].ammo_category == "bullet")
          assert(detail.effects[2].type == "worker-robot-storage" and detail.effects[2].modifier == 1)
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
          local declared = {{id = id, family = "research_gears"}}
          local rows = model.rows(force, declared, {}, {[id] = "Gears"}, context)
          assert(#rows == 1 and rows[1].current_level == 6 and rows[1].queued_count == 1)
          assert(rows[1].completed_count == nil and rows[1].cap == 10 and rows[1].cap_state == "finite")
          local detail = assert(model.detail(force, declared, {selected = id}, {}, context))
          assert(detail.cost.ingredients[1].name == "automation-science-pack")
          assert(detail.effects[1].recipe == "iron-gear-wheel" and detail.effects[1].change == .1)
          assert(#reads == 0, table.concat(reads, ", "))
        ''')

    def test_model_does_not_import_generator_or_touch_host_globals(self):
        source = (ROOT / "source/presentation/library_model.lua").read_text(encoding="utf-8")
        availability = (ROOT / "source/presentation/availability.lua").read_text(encoding="utf-8")
        catalogue = (ROOT / "source/research/catalogue.lua").read_text(encoding="utf-8")
        self.assertNotIn("require(", source)
        self.assertNotIn("Generator", source)
        self.assertNotIn("require(", availability)
        for forbidden in ("game.", "storage.", "data.raw", "pairs(technologies)", "technology_id"):
            self.assertNotIn(forbidden, availability)
        self.assertIn('require("compatibility.modern_catalogue")', catalogue)
        for forbidden in ('require("research.generator")', 'require("research.modern")',
                          'require("research.settings")', "data.raw", "game.", "storage."):
            self.assertNotIn(forbidden, catalogue)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LibraryModelTests))
    sys.exit(0 if result.wasSuccessful() else 1)

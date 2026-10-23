"""Pure controls for selected-target API capabilities and reduced stage adapters."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
DATA_API = "__more-infinite-research__.api.v1.data"


class TargetAdapterTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          package.preload["__more-infinite-research__/research/generator"] = function()
            return require("research.generator")
          end
          package.preload["__more-infinite-research__.api.v1.data"] = function()
            return assert(loadfile(player_root .. "/api/v1/data.lua"))()
          end

          function target(id, research_levels, recipe_productivity)
            return {
              id=id, factorio_version="legacy", minimum_base="0.13.0",
              distribution_version="5.0." .. id, reduced=true,
              research_levels=research_levels, recipe_productivity=recipe_productivity,
            }
          end

          function load_data_api(metadata)
            package.loaded["platform.target"] = nil
            package.loaded["__more-infinite-research__.api.v1.data"] = nil
            package.preload["platform.target"] = function() return metadata end
            return require("__more-infinite-research__.api.v1.data")
          end

          function load_runtime_api(metadata)
            package.loaded["platform.target"] = nil
            package.loaded["api.v1.runtime"] = nil
            package.preload["platform.target"] = function() return metadata end
            return require("api.v1.runtime")
          end

          function load_adapter(stage, metadata)
            package.loaded["platform.target"] = nil
            package.loaded["adapters.reduced." .. stage] = nil
            package.preload["platform.target"] = function() return metadata end
            if stage == "control" then package.loaded["api.v1.runtime"] = nil end
            return assert(loadfile(player_root .. "/adapters/reduced/" .. stage .. ".lua"))()
          end

          function api_stage()
            local stage = {
              raw = {
                technology={automation={}}, tool={["automation-science-pack"]={}},
                recipe={["iron-gear-wheel"]={}}
              },
              writes=0,
            }
            function stage:extend(rows)
              self.writes = self.writes + 1
              for _, row in ipairs(rows) do
                self.raw[row.type] = self.raw[row.type] or {}
                self.raw[row.type][row.name] = row
              end
            end
            return stage
          end

          function api_definition(name)
            return {
              type="technology", name=name, prerequisites={"automation"}, effects={},
              unit={count=10, ingredients={{"automation-science-pack", 1}}, time=15},
            }
          end

          function historical_stage(id)
            local contracts, definitions = require("compatibility.historical_direct"), require("research.native_direct_definitions")
            local continuation_contracts = require("compatibility.historical_continuations")
            local raw = {technology={}, tool={}, item={}}
            for _, row in ipairs(contracts.for_target(id).emitted) do
              for _, prerequisite in ipairs(row.prerequisites) do raw.technology[prerequisite] = {icon="test/technology.png", icon_size=64} end
              for _, science in ipairs(row.science) do raw.tool[science] = {} end
              for _, candidate in ipairs(definitions.definition(row.key).icon_candidates) do
                if candidate.technology then raw.technology[candidate.technology] = {icon="test/icon.png", icon_size=64} end
                if candidate.item then raw.item[candidate.item] = {icon="test/icon.png", icon_size=64} end
              end
            end
            local continuation = continuation_contracts.for_target(id)
            local source_time = {
              ["braking-force"]=60, ["inserter-capacity-bonus"]=30, ["research-speed"]=30,
              ["weapon-shooting-speed"]=60, ["worker-robots-storage"]=60, ["laser-shooting-speed"]=60,
            }
            for _, row in ipairs(continuation.rows) do
              for _, prerequisite in ipairs(row.prerequisites) do
                raw.technology[prerequisite] = {icon="test/technology.png", icon_size=64,
                  order="other-" .. prerequisite, unit={count=1, time=30}}
              end
              for _, ingredient in ipairs(row.science) do raw.tool[ingredient[1]] = {} end
              local time = source_time[row.family]
              raw.technology[row.predecessor] = {icon="test/icon.png", icon_size=64, order=row.order,
                unit={count=row.expected_predecessor_count, time=time},
                max_level=continuation.numeric and nil or row.level - 1}
              raw.technology[row.previous] = {icon="test/icon.png", icon_size=64,
                unit={count=row.expected_previous_count, time=time},
                max_level=continuation.numeric and nil or row.level - 2}
            end
            local lab_inputs = {}
            for name in pairs(raw.tool) do lab_inputs[#lab_inputs + 1] = name end
            table.sort(lab_inputs)
            raw.lab = {fixture={inputs=lab_inputs}}
            local stage = {raw=raw, writes=0}
            function stage:extend(rows)
              self.writes = self.writes + 1
              for _, row in ipairs(rows) do self.raw.technology[row.name] = row end
            end
            return stage
          end
        ''')

    def test_default_target_preserves_f210_api_metadata_and_capabilities(self):
        self.lua.execute(r'''
          package.preload["platform.target"] = nil
          package.loaded["platform.target"] = nil
          package.loaded["__more-infinite-research__.api.v1.data"] = nil
          local selected = require("platform.target")
          assert(selected.id == "f210" and selected.factorio_version == "2.1")
          assert(selected.minimum_base == "2.1.23" and selected.distribution_version == "5.0.21000")
          assert(not selected.reduced and selected.research_levels and selected.recipe_productivity)
          local api = require("__more-infinite-research__.api.v1.data")
          assert(api.get_version().product == "5.0.21000")
          assert(api.get_capabilities().technology_creation and api.get_capabilities().recipe_productivity)
        ''')

    def test_reduced_data_and_settings_adapters_are_target_bound_and_skip_library(self):
        self.lua.execute(r'''
          package.loaded["presentation.shortcut"] = nil
          local data_adapter = load_adapter("data", target("f013", false, false))
          data_adapter.apply()
          assert(package.loaded["presentation.shortcut"] == nil)

          data = {rows={}}
          function data:extend(rows) self.rows = rows end
          local settings_adapter = load_adapter("settings", target("f013", false, false))
          settings_adapter.apply()
          assert(#data.rows == 63, "F013 has nine direct setting groups")
          assert(package.loaded["research.settings"] == nil)
        ''')

    def test_reduced_final_fixes_selects_only_the_historical_contract(self):
        self.lua.execute(r'''
          data, settings = historical_stage("f013"), {startup={}}
          local adapter = load_adapter("data-final-fixes", target("f013", false, false))
          adapter.apply()
          assert(data.writes == 1 and data.raw.technology["recipe-prod-research_cannon_shooting_speed-1"] == nil)
          assert(data.raw.technology["recipe-prod-research_rocket_shooting_speed-1"].enabled ~= false)
          assert(data.raw.technology["recipe-prod-research_rocket_shooting_speed-1"].unit.count == 60)
          assert(data.raw.technology["inserter-capacity-bonus-8"].unit.count == 914489)
          assert(data.raw.technology["worker-robots-storage-4"].unit.count_formula == nil)
          local direct, continuations = 0, 0
          for name in pairs(data.raw.technology) do
            if name:find("recipe-prod-", 1, true) == 1 then direct = direct + 1 end
            if name == "inserter-capacity-bonus-8" or name == "worker-robots-storage-4" then
              continuations = continuations + 1
            end
          end
          assert(direct == 7 and continuations == 2)
          assert(package.loaded["presentation.library"] == nil and package.loaded["runtime.bootstrap"] == nil)
        ''')

    def test_reduced_final_fixes_selects_the_late_six_continuation_contract(self):
        self.lua.execute(r'''
          data, settings = historical_stage("f110"), {startup={}}
          local adapter = load_adapter("data-final-fixes", target("f110", true, false))
          adapter.apply()
          local laser = data.raw.technology["laser-shooting-speed-8"]
          assert(data.writes == 1 and laser and laser.level == 8 and laser.max_level == "infinite")
          assert(laser.enabled ~= false)
          assert(laser.unit.count_formula == "1*(1025.15625*1.5^(L-8))")
          assert(data.raw.technology["worker-robots-speed-6"] == nil)
          local continuations = 0
          for _, name in ipairs({"braking-force-8", "inserter-capacity-bonus-8", "research-speed-7",
              "weapon-shooting-speed-7", "worker-robots-storage-4", "laser-shooting-speed-8"}) do
            if data.raw.technology[name] then continuations = continuations + 1 end
          end
          assert(continuations == 6)
        ''')

    def test_reduced_control_registers_only_the_unified_api(self):
        self.lua.execute(r'''
          local calls = 0
          remote = {interfaces={}}
          function remote.add_interface(name, members)
            calls = calls + 1
            remote.interfaces[name] = members
          end
          local adapter = load_adapter("control", target("f013", false, false))
          adapter.apply()
          assert(calls == 1 and remote.interfaces["more-infinite-research.api.v1"])
          assert(package.loaded["runtime.bootstrap"] == nil and package.loaded["presentation.library"] == nil)
          game = setmetatable({}, {__index=function() error("old target query must not inspect game") end})
          local status, code = remote.interfaces["more-infinite-research.api.v1"].get_research(1, "finite")
          assert(status == nil and code == "unsupported_capability")
        ''')

    def test_reduced_control_accepts_an_indexable_non_table_remote_proxy(self):
        class RemoteProxy:
            def __init__(self, lua):
                self.interfaces = lua.table()
                self.calls = 0

            def add_interface(self, name, members):
                self.calls += 1
                self.interfaces[name] = members

        proxy = RemoteProxy(self.lua)
        self.lua.globals().remote = proxy
        self.assertNotEqual(self.lua.eval("type(remote)"), "table")
        self.lua.execute(r'''
          local adapter = load_adapter("control", target("f013", false, false))
          adapter.apply()
          assert(remote.interfaces["more-infinite-research.api.v1"] ~= nil)
        ''')
        self.assertEqual(proxy.calls, 1)

    def test_reduced_control_rejects_missing_or_colliding_interface_before_registration(self):
        self.lua.execute(r'''
          local calls = 0
          remote = {}
          function remote.add_interface() calls = calls + 1 end
          local adapter = load_adapter("control", target("f013", false, false))
          local ok, message = pcall(adapter.apply)
          assert(not ok and tostring(message):find("readable remote.interfaces", 1, true))
          assert(calls == 0)

          remote = {interfaces={["more-infinite-research.api.v1"]={}}}
          function remote.add_interface() calls = calls + 1 end
          adapter = load_adapter("control", target("f013", false, false))
          ok, message = pcall(adapter.apply)
          assert(not ok and tostring(message):find("already exists", 1, true))
          assert(calls == 0)
        ''')

    def test_reduced_productivity_capability_rejects_all_direct_paths_before_writes(self):
        self.lua.execute(r'''
          local api = load_data_api(target("f013", false, false))
          data = api_stage()
          assert(not api.get_capabilities().recipe_productivity)
          local product = api_definition("reduced-productivity-effect")
          product.effects = {{type="change-recipe-productivity", recipe="iron-gear-wheel", change=.02}}
          local ok, message = pcall(api.add_technology, product)
          assert(not ok and tostring(message):find("MIR_API:unsupported_capability", 1, true))
          assert(data.writes == 0)
          ok, message = pcall(api.add_productivity, api_definition("reduced-productivity-helper"), {"iron-gear-wheel"}, .02)
          assert(not ok and tostring(message):find("MIR_API:unsupported_capability", 1, true))
          assert(data.writes == 0)
          assert(api.add_technology(api_definition("reduced-ordinary")) == "reduced-ordinary" and data.writes == 1)
        ''')

    def test_all_reduced_targets_report_no_recipe_productivity_and_013_014_have_no_level_query(self):
        self.lua.execute(r'''
          local ids = {"f013", "f014", "f015", "f016", "f017", "f100", "f110"}
          for _, id in ipairs(ids) do
            local api = load_data_api(target(id, id ~= "f013" and id ~= "f014", false))
            assert(not api.get_capabilities().recipe_productivity, id)
          end
          for _, id in ipairs({"f013", "f014"}) do
            local api = load_runtime_api(target(id, false, false))
            game = setmetatable({}, {__index=function() error("unsupported query inspected game") end})
            local status, code = api.get_research(1, "finite")
            assert(status == nil and code == "unsupported_capability", id)
          end
        ''')

    def test_level_query_omits_an_unavailable_optional_saved_progress(self):
        self.lua.execute(r'''
          local api = load_runtime_api(target("f110", true, false))
          local technology = setmetatable({
            researched=true, level=4, enabled=true, prototype={max_level="infinite"},
          }, {__index=function(_, key)
            if key == "saved_progress" then error("not provided on this target") end
          end})
          game = {forces={[7]={valid=true, technologies={finite=technology}}}}
          local status, code = api.get_research(7, "finite")
          assert(code == nil and status.level == 4 and status.max_level == "infinite")
          assert(status.saved_progress == nil and api.get_capabilities().research_query)
        ''')

    def test_level_query_returns_unsupported_for_unavailable_required_members(self):
        self.lua.execute(r'''
          local api = load_runtime_api(target("f110", true, false))
          local function query(technology)
            game = {forces={[7]={valid=true, technologies={finite=technology}}}}
            return api.get_research(7, "finite")
          end
          local missing_level = setmetatable({researched=true, enabled=true, prototype={max_level="infinite"}}, {
            __index=function(_, key) if key == "level" then error("unsupported level") end end,
          })
          local status, code = query(missing_level)
          assert(status == nil and code == "unsupported_capability")
          local missing_prototype = setmetatable({researched=true, enabled=true, level=1}, {
            __index=function(_, key) if key == "prototype" then error("unsupported prototype") end end,
          })
          status, code = query(missing_prototype)
          assert(status == nil and code == "unsupported_capability")
          local missing_maximum = setmetatable({}, {
            __index=function(_, key) if key == "max_level" then error("unsupported maximum") end end,
          })
          status, code = query({researched=true, enabled=true, level=1, prototype=missing_maximum})
          assert(status == nil and code == "unsupported_capability")
        ''')

    def test_reduced_adapters_contain_no_library_or_event_maintenance(self):
        root = ROOT / "source/mir5/adapters/reduced"
        text = "\n".join(path.read_text() for path in root.glob("*.lua"))
        self.assertNotIn("presentation.library", text)
        self.assertNotIn("runtime.bootstrap", text)
        self.assertNotIn("on_event", text)
        self.assertNotIn("on_nth_tick", text)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(TargetAdapterTests))
    sys.exit(0 if result.wasSuccessful() else 1)

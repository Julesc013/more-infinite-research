"""Host controls for the fixed F200 Expanded Productivity Research overlap.

These replay independently captured named EPR tails and MIR counterpart effects.
They do not establish a Factorio save or gameplay result.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
PLAYER = ROOT / "source/mir5"
FACTS_PATH = ROOT / "tests/mir5/fixtures/competing-epr-f200-captured-facts.json"

# Captured from verified F200 2.0.77 upstream/published EPR 1.3.8 run
# 39999658774, under build/mir5/black-glass/incoming/39999658774.
# Each replacement group is intentionally explicit: petroleum needs two MIR
# technologies, while the six standard packs share one MIR technology.
EXPECTED = (
    ("epr_advanced-circuit-productivity-5", 5, ("advanced-circuit",), (("recipe-prod-research_advanced_circuit-1", ("advanced-circuit",)),)),
    ("epr_automation-science-pack-productivity-5", 5, ("automation-science-pack",), (("recipe-prod-research_science_pack_productivity-1", ("automation-science-pack",)),)),
    ("epr_battery-productivity-5", 5, ("battery",), (("recipe-prod-research_batteries-1", ("battery",)),)),
    ("epr_chemical-science-pack-productivity-5", 5, ("chemical-science-pack",), (("recipe-prod-research_science_pack_productivity-1", ("chemical-science-pack",)),)),
    ("epr_copper-cable-productivity-5", 5, ("copper-cable",), (("recipe-prod-research_copper_cable-1", ("copper-cable",)),)),
    ("epr_copper-plate-productivity-5", 5, ("copper-plate",), (("recipe-prod-research_copper-1", ("copper-plate",)),)),
    ("epr_electric-engine-unit-productivity-4", 4, ("electric-engine-unit",), (("recipe-prod-research_electric_engine-1", ("electric-engine-unit",)),)),
    ("epr_electronic-circuit-productivity-5", 5, ("electronic-circuit",), (("recipe-prod-research_electronic_circuit-1", ("electronic-circuit",)),)),
    ("epr_engine-unit-productivity-5", 5, ("engine-unit",), (("recipe-prod-research_engine-1", ("engine-unit",)),)),
    ("epr_explosives-productivity-5", 5, ("explosives",), (("recipe-prod-research_explosives-1", ("explosives",)),)),
    ("epr_flying-robot-frame-productivity-4", 4, ("flying-robot-frame",), (("recipe-prod-research_flying_robot_frame-1", ("flying-robot-frame",)),)),
    ("epr_heavy-oil-productivity-4", 4, ("advanced-oil-processing", "coal-liquefaction"), (("recipe-prod-research_oil_processing_productivity-1", ("advanced-oil-processing", "coal-liquefaction")),)),
    ("epr_iron-gear-wheel-productivity-5", 5, ("iron-gear-wheel",), (("recipe-prod-research_gears-1", ("iron-gear-wheel",)),)),
    ("epr_iron-plate-productivity-5", 5, ("iron-plate",), (("recipe-prod-research_iron-1", ("iron-plate",)),)),
    ("epr_iron-stick-productivity-5", 5, ("iron-stick",), (("recipe-prod-research_iron_sticks-1", ("iron-stick",)),)),
    ("epr_light-oil-productivity-4", 4, ("heavy-oil-cracking",), (("recipe-prod-research_oil_cracking_productivity-1", ("heavy-oil-cracking",)),)),
    ("epr_logistic-science-pack-productivity-5", 5, ("logistic-science-pack",), (("recipe-prod-research_science_pack_productivity-1", ("logistic-science-pack",)),)),
    ("epr_low-density-structure-productivity-4", 4, ("low-density-structure",), (("recipe-prod-research_low_density_structure-1", ("low-density-structure",)),)),
    ("epr_lubricant-productivity-4", 4, ("lubricant",), (("recipe-prod-research_lubricant_productivity-1", ("lubricant",)),)),
    ("epr_military-science-pack-productivity-5", 5, ("military-science-pack",), (("recipe-prod-research_science_pack_productivity-1", ("military-science-pack",)),)),
    ("epr_petroleum-gas-productivity-5", 5, ("basic-oil-processing", "light-oil-cracking"), (("recipe-prod-research_oil_processing_productivity-1", ("basic-oil-processing",)), ("recipe-prod-research_oil_cracking_productivity-1", ("light-oil-cracking",)))),
    ("epr_plastic-bar-productivity-5", 5, ("plastic-bar",), (("recipe-prod-research_plastic-1", ("plastic-bar",)),)),
    ("epr_processing-unit-productivity-4", 4, ("processing-unit",), (("recipe-prod-research_processing_unit-1", ("processing-unit",)),)),
    ("epr_production-science-pack-productivity-4", 4, ("production-science-pack",), (("recipe-prod-research_science_pack_productivity-1", ("production-science-pack",)),)),
    ("epr_rocket-fuel-productivity-4", 4, ("rocket-fuel",), (("recipe-prod-research_rocket_fuel-1", ("rocket-fuel",)),)),
    ("epr_steel-plate-productivity-5", 5, ("steel-plate",), (("recipe-prod-research_steel-1", ("steel-plate",)),)),
    ("epr_stone-brick-productivity-5", 5, ("stone-brick",), (("recipe-prod-research_concrete-1", ("stone-brick",)),)),
    ("epr_sulfur-productivity-5", 5, ("sulfur",), (("recipe-prod-research_sulfur-1", ("sulfur",)),)),
    ("epr_sulfuric-acid-productivity-5", 5, ("sulfuric-acid",), (("recipe-prod-research_sulfuric_acid_productivity-1", ("sulfuric-acid",)),)),
    ("epr_utility-science-pack-productivity-4", 4, ("utility-science-pack",), (("recipe-prod-research_science_pack_productivity-1", ("utility-science-pack",)),)),
)


def plain(value, seen=None):
    if not hasattr(value, "items"):
        return value
    seen = set() if seen is None else seen
    if id(value) in seen:
        raise AssertionError("cyclic Lua value")
    seen.add(id(value))
    keys = list(value.keys())
    if keys and all(isinstance(key, int) and key > 0 for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        result = [plain(value[index], seen) for index in range(1, len(keys) + 1)]
    else:
        result = {key: plain(item, seen) for key, item in value.items()}
    seen.remove(id(value))
    return result


class CompetingProductivityTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = PLAYER.as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          function exact_active() return {base="2.0.77", ExpandedProductivityResearch="1.3.8"} end
          function f200_target() return {id="f200", factorio_version="2.0"} end
          function add_effects(out, effects)
            for _, effect in ipairs(effects) do out[#out + 1] = {type=effect.type or "change-recipe-productivity", recipe=effect.recipe, change=effect.change} end
          end
          function force_from_contract(contract)
            local force = {index=71, valid=true, technologies={}, research_queue={}, research_progress=.42}
            for _, item in ipairs(contract.bindings) do
              force.technologies[item.id] = {
                name=item.id, valid=true, force=force, level=item.first_level, researched=false,
                enabled=true, visible_when_disabled=false,
                prototype={enabled=true, level=item.first_level, max_level=4294967295, effects={},
                  prerequisites={[item.predecessor]={name=item.predecessor}}}
              }
              add_effects(force.technologies[item.id].prototype.effects, item.effects)
              for _, replacement in ipairs(item.replacements) do
                local target = force.technologies[replacement.id]
                if not target then
                  target = {name=replacement.id, valid=true, force=force, level=1, researched=false,
                    enabled=true, visible_when_disabled=false,
                    prototype={enabled=true, max_level=4294967295, effects={}}}
                  force.technologies[replacement.id] = target
                end
                add_effects(target.prototype.effects, replacement.effects)
              end
            end
            return force
          end
          function install_competing(preference, force)
            local target = require("platform.target")
            target.id, target.factorio_version = "f200", "2.0"
            script = {active_mods=exact_active()}
            storage = storage or {}
            game = {forces={[force.index]=force, player=force}}
            package.loaded["runtime.configuration"] = nil
            package.loaded["runtime.competing_productivity"] = nil
            package.preload["runtime.configuration"] = function()
              return {options={["mir-prefer-this-mod-for-competing-techs"]=preference}}
            end
            return require("runtime.competing_productivity")
          end
        ''')

    def contract(self):
        return self.lua.execute('return require("compatibility.competing_productivity").select(exact_active(), f200_target())')

    def captured_facts(self):
        return json.loads(FACTS_PATH.read_text(encoding="utf-8"))

    def assert_captured_fact_inventory(self, facts):
        self.assertEqual(1, facts["schema"])
        self.assertEqual("mir5-f200-competing-epr-captured-facts", facts["kind"])
        self.assertEqual({"base": "2.0.77", "ExpandedProductivityResearch": "1.3.8"}, facts["required_mods"])
        self.assertEqual(30, facts["transition"]["removed_epr_infinite_tail_count"])
        self.assertEqual(54, facts["transition"]["published_technology_addition_count"])
        self.assertEqual(30, len(facts["removed_epr_tails"]))
        self.assertEqual(54, len(facts["published_mir_additions"]))
        self.assertEqual(30, len(facts["binding_coverage"]))
        self.assertEqual(
            ["epr_barrel-productivity-5", "epr_nuclear-fuel-productivity-3", "epr_rocket-part-productivity-2",
             "epr_solid-fuel-productivity-5", "epr_uranium-235-productivity-4", "epr_uranium-fuel-cell-productivity-4"],
            facts["transition"]["retained_epr_infinite_tail_names"],
        )

        expected = {row[0]: row for row in EXPECTED}
        additions = {row["name"]: row for row in facts["published_mir_additions"]}
        removed = {row["name"]: row for row in facts["removed_epr_tails"]}
        self.assertEqual(set(expected), set(removed))
        self.assertEqual(54, len(additions))
        self.assertEqual(54, len(set(additions)))
        for coverage in facts["binding_coverage"]:
            name = coverage["foreign"]
            _, level, recipes, replacements = expected[name]
            self.assertEqual(level, coverage["first_level"])
            self.assertEqual(f"{name[:-1]}{level - 1}", coverage["predecessor"])
            self.assertEqual(recipes, tuple(effect["recipe"] for effect in coverage["foreign_effects"]))
            self.assertEqual({target for target, _ in replacements}, set(coverage["mir_replacements"]))
            self.assertEqual(coverage["foreign_effects"], removed[name]["effects"])
            for replacement in coverage["mir_replacements"]:
                self.assertIn(replacement, additions)

    def verify_local_capture_subset(self, facts):
        """Compare every committed selected row when the ignored raw captures exist."""
        captures = facts["captures"]
        raw_paths = {name: ROOT / entry["path"] for name, entry in captures.items()}
        if not all(path.is_file() for path in raw_paths.values()):
            return
        for name, path in raw_paths.items():
            self.assertEqual(captures[name]["sha256"], hashlib.sha256(path.read_bytes()).hexdigest().upper())
            settings = ROOT / captures[name]["mod_settings_path"]
            self.assertTrue(settings.is_file())
            self.assertEqual(captures[name]["mod_settings_sha256"], hashlib.sha256(settings.read_bytes()).hexdigest().upper())

        raw = {name: json.loads(path.read_text(encoding="utf-8"))["technology"] for name, path in raw_paths.items()}
        upstream, published, foreign = raw["upstream"], raw["published"], raw["foreign"]
        removed_names = {row["name"] for row in facts["removed_epr_tails"]}
        addition_names = {row["name"] for row in facts["published_mir_additions"]}
        self.assertEqual(removed_names, {name for name in upstream if name.startswith("epr_") and name not in published})
        self.assertEqual(addition_names, set(published).difference(upstream))
        for row in facts["removed_epr_tails"]:
            self.assertEqual(row, upstream[row["name"]])
            self.assertEqual(row, foreign[row["name"]])
        for row in facts["published_mir_additions"]:
            self.assertEqual(row, published[row["name"]])

        def effect_key(effect):
            if effect.get("type") != "change-recipe-productivity":
                return None
            return effect["type"], effect["recipe"], effect["change"]

        for coverage in facts["binding_coverage"]:
            foreign_effects = {effect_key(effect) for effect in upstream[coverage["foreign"]]["effects"]}
            self.assertNotIn(None, foreign_effects)
            actual_replacements = sorted({
                candidate
                for candidate in addition_names
                if any(effect_key(effect) in foreign_effects for effect in published[candidate].get("effects", ()))
            })
            self.assertEqual(coverage["mir_replacements"], actual_replacements)

        for name, expected_value in (("published", True), ("foreign", False)):
            setting = json.loads((ROOT / captures[name]["mod_settings_path"]).read_text(encoding="utf-8"))
            actual = setting["bool-setting"]["mir-prefer-this-mod-for-competing-techs"]["default_value"]
            self.assertEqual(expected_value, actual)

    def test_independent_f200_binding_inventory_and_captured_facts(self):
        facts = self.captured_facts()
        self.assert_captured_fact_inventory(facts)
        self.verify_local_capture_subset(facts)
        contract = plain(self.contract())
        actual = []
        for item in contract["bindings"]:
            actual.append((item["id"], item["first_level"], tuple(effect["recipe"] for effect in item["effects"]),
                           tuple((replacement["id"], tuple(effect["recipe"] for effect in replacement["effects"]))
                                 for replacement in item["replacements"])))
        self.assertEqual(EXPECTED, tuple(actual))
        self.assertEqual(30, len(actual))
        self.assertEqual({4, 5}, {row[1] for row in actual})
        self.assertTrue(all(row[0].endswith(f"-{row[1]}") for row in actual))
        self.assertEqual(tuple(f"{row[0][:-1]}{row[1] - 1}" for row in actual),
                         tuple(item["predecessor"] for item in contract["bindings"]))

        self.lua.execute('''
          local binding = require("compatibility.competing_productivity")
          assert(binding.select({base="2.0.77", ExpandedProductivityResearch="1.3.9"}, f200_target()) == nil)
          assert(binding.select(exact_active(), {id="f210", factorio_version="2.1"}) == nil)
          assert(binding.runtime_effects_match({{type="change-recipe-productivity",recipe="iron-plate",change=.10000000149}},
            {{recipe="iron-plate",change=.1}}))
          assert(not binding.runtime_effects_match({{type="change-recipe-productivity",recipe="iron-plate",change=.1001}},
            {{recipe="iron-plate",change=.1}}))
        ''')

    def test_runtime_caps_only_exact_known_foreign_bindings_and_restores_only_its_rights(self):
        self.lua.execute(r'''
          local binding = require("compatibility.competing_productivity")
          local contract = binding.select(exact_active(), f200_target())
          local inactive_force = force_from_contract(contract)
          storage = {}
          local inactive = install_competing(false, inactive_force)
          assert(inactive.active() == false)
          inactive.on_init()
          assert(storage.mir_competing_productivity == nil)
          local force = force_from_contract(contract)
          storage = {}
          local first = contract.bindings[1]

          -- A data-stage observation is not runtime authority. A provider
          -- that changes either named native boundary remains wholly foreign.
          local wrong_level = force_from_contract(contract)
          wrong_level.technologies[first.id].prototype.level = first.first_level - 1
          local malformed = install_competing(true, wrong_level)
          malformed.on_init()
          assert(wrong_level.technologies[first.id].enabled == true
            and wrong_level.technologies[first.id].visible_when_disabled == false)
          assert(storage.mir_competing_productivity.owned_disabled[wrong_level.index][first.id] == nil)

          local missing_predecessor = force_from_contract(contract)
          missing_predecessor.technologies[first.id].prototype.prerequisites[first.predecessor] = nil
          storage = {}
          malformed = install_competing(true, missing_predecessor)
          malformed.on_init()
          assert(missing_predecessor.technologies[first.id].enabled == true
            and missing_predecessor.technologies[first.id].visible_when_disabled == false)
          assert(storage.mir_competing_productivity.owned_disabled[missing_predecessor.index][first.id] == nil)

          storage = {}
          force.technologies[first.id].enabled = false
          force.technologies[first.id].visible_when_disabled = false
          force.technologies[first.id].prototype.effects[1].change = .10000000149
          local unrelated = {name="automation", valid=true}
          force.research_queue = {force.technologies[first.id], unrelated}
          local runtime = install_competing(true, force)
          assert(runtime.active())
          runtime.on_init()
          for _, item in ipairs(contract.bindings) do
            local value = force.technologies[item.id]
            assert(value.level == item.first_level and value.researched == false)
            assert(value.enabled == false and value.visible_when_disabled == true)
          end
          assert(#force.research_queue == 1 and force.research_queue[1] == unrelated and force.research_progress == .42)
          assert(storage.mir_competing_productivity.owned_disabled[force.index][first.id].disabled == nil)

          -- A false preference releases only records owned by this module. The
          -- pre-disabled foreign tail keeps its disabled state and baseline visibility.
          runtime = install_competing(false, force)
          assert(runtime.active() == false)
          runtime.on_configuration_changed()
          assert(force.technologies[first.id].enabled == false and force.technologies[first.id].visible_when_disabled == false)
          for index = 2, #contract.bindings do
            local value = force.technologies[contract.bindings[index].id]
            assert(value.enabled == true and value.visible_when_disabled == false)
          end
          assert(storage.mir_competing_productivity == nil)

          runtime = install_competing(true, force)
          force.technologies[first.id].enabled = true
          runtime.on_configuration_changed()
          assert(force.technologies[first.id].enabled == false)
          -- A changed native EPR effect invalidates ownership but does not
          -- manufacture an enablement write for the foreign technology.
          force.technologies[first.id].prototype.effects[1].change = .2
          runtime.on_configuration_changed()
          assert(force.technologies[first.id].enabled == false)
          assert(storage.mir_competing_productivity.owned_disabled[force.index][first.id] == nil)

          local petroleum = "epr_petroleum-gas-productivity-5"
          assert(force.technologies[petroleum].enabled == false)
          force.technologies["recipe-prod-research_oil_cracking_productivity-1"].prototype.effects[2].change = .2
          runtime.on_configuration_changed()
          assert(force.technologies[petroleum].enabled == true and force.technologies[petroleum].visible_when_disabled == false)

          local reads = 0
          game = setmetatable({}, {__index=function() reads = reads + 1; error("on_load accessed game") end})
          local saved = storage
          storage = setmetatable(saved, {__index=function(_, key) reads = reads + 1; error("on_load accessed storage " .. tostring(key)) end})
          runtime.on_load()
          assert(reads == 0)
        ''')

    def test_bootstrap_registers_the_single_named_event_composition(self):
        self.lua.execute(r'''
          local calls, handlers = {}, {events={}}
          package.preload["platform.target"] = function() return {id="f200", factorio_version="2.0"} end
          package.preload["runtime.lifecycle"] = function()
            return {caps_active=function() return false end, cap_limits=function() return {} end,
              on_init=function() end, on_configuration_changed=function() end, on_load=function() end}
          end
          package.preload["runtime.competing_productivity"] = function()
            local module = {active=function() return true end}
            for _, name in ipairs({"on_init", "on_configuration_changed", "on_load", "on_force_created", "on_force_reset",
              "on_forces_merged", "on_research_finished", "on_research_reversed", "on_technology_effects_reset",
              "on_research_started", "on_research_cancelled"}) do
              module[name] = function(event) calls[name] = (calls[name] or 0) + 1 end
            end
            return module
          end
          package.preload["runtime.library"] = function()
            return {translation_maintenance_ticks=61, set_cap_provider=function() end, subscription_needs=function() return false end,
              on_init=function() end, on_configuration_changed=function() end, on_load=function() end,
              on_lua_shortcut=function() end, on_gui_text_changed=function() end, on_gui_selected_tab_changed=function() end,
              on_gui_selection_state_changed=function() end, on_gui_click=function() end, on_gui_location_changed=function() end,
              on_gui_closed=function() end, on_player_removed=function() end, on_string_translated=function() end,
              on_player_locale_changed=function() end, on_player_changed_force=function() end, on_player_joined_game=function() end,
              open=function() return nil end}
          end
          package.preload["research.catalogue"] = function() return {declared=function() return {} end} end
          package.preload["api.v1.runtime"] = function() return {get_version=function() return {} end, get_capabilities=function() return {} end, get_research=function() return {} end} end
          package.preload["runtime.settings_profile"] = function() return {export_string=function() return "" end, validate_string=function() return {} end} end
          package.preload["runtime.settings_commands"] = function() return {export=function() end, validate=function() end} end
          package.preload["runtime.configuration"] = function() return {passive_repair_enabled=false} end
          package.preload["runtime.passive_repair"] = function() return {repair_interval_ticks=60, reconcile=function() return nil, {needs_schedule=false} end, on_load=function() return {needs_schedule=false} end} end
          package.preload["runtime.spoilage_contribution"] = function() return {} end
          script = {active_mods={ExpandedProductivityResearch="1.3.8"}, on_init=function(f) handlers.init=f end,
            on_configuration_changed=function(f) handlers.configuration=f end, on_load=function(f) handlers.load=f end,
            on_event=function(id, f) handlers.events[id]=f end, on_nth_tick=function() end}
          defines = {events={on_force_created=1,on_force_reset=2,on_forces_merged=3,on_research_finished=4,
            on_research_started=5,on_research_cancelled=6,on_research_reversed=7,on_technology_effects_reset=8}}
          remote={interfaces={},add_interface=function(name, value) remote.interfaces[name]=value end}
          commands={add_command=function() end}
          storage={}; game={forces={}}
          local bootstrap = require("runtime.bootstrap")
          bootstrap.register()
          handlers.init(); handlers.configuration({}); handlers.load()
          handlers.events[1]({force={index=1}}); handlers.events[2]({force={index=1}})
          handlers.events[3]({source_index=1,destination={index=2}})
          handlers.events[4]({research={name="epr_iron-plate-productivity-5",force={index=1}}})
          handlers.events[5]({research={name="epr_iron-plate-productivity-5",force={index=1}}})
          handlers.events[6]({research={name="epr_iron-plate-productivity-5",force={index=1}}})
          handlers.events[7]({research={name="epr_iron-plate-productivity-5",force={index=1}}})
          handlers.events[8]({force={index=1}})
          for _, name in ipairs({"on_init", "on_configuration_changed", "on_load", "on_force_created", "on_force_reset",
            "on_forces_merged", "on_research_finished", "on_research_started", "on_research_cancelled",
            "on_research_reversed", "on_technology_effects_reset"}) do assert(calls[name] == 1, name) end

          -- Removing the provider may erase its rows before another profile
          -- adds a new foreign EPR technology. The private right is stale;
          -- clearing it must not re-enable or reveal the newly foreign row.
          local foreign = {enabled=false, visible_when_disabled=false, level=1, researched=false}
          handlers = {events={}}
          remote={interfaces={},add_interface=function(name, value) remote.interfaces[name]=value end}
          script = {active_mods={}, on_init=function(f) handlers.init=f end,
            on_configuration_changed=function(f) handlers.configuration=f end, on_load=function(f) handlers.load=f end,
            on_event=function(id, f) handlers.events[id]=f end, on_nth_tick=function() end}
          storage = {mir_competing_productivity={schema=1, owned_disabled={[81]={
            ["epr_iron-plate-productivity-5"]={disabled=true, visible_when_disabled=false}}}}}
          game = {forces={[81]={index=81, technologies={["epr_iron-plate-productivity-5"]=foreign}}}}
          package.loaded["runtime.bootstrap"] = nil
          local without_provider = require("runtime.bootstrap")
          without_provider.register()
          handlers.configuration({})
          assert(storage.mir_competing_productivity == nil)
          assert(foreign.enabled == false and foreign.visible_when_disabled == false
            and foreign.level == 1 and foreign.researched == false)

          handlers = {events={}}
          remote={interfaces={},add_interface=function(name, value) remote.interfaces[name]=value end}
          storage = {mir_competing_productivity={schema=2, owned_disabled={}}}
          package.loaded["runtime.bootstrap"] = nil
          without_provider = require("runtime.bootstrap")
          without_provider.register()
          local ok, message = pcall(handlers.configuration, {})
          assert(not ok and tostring(message):match("unsupported competing productivity storage"))
        ''')

    def test_source_stays_fixed_and_non_scanning(self):
        compatibility = (PLAYER / "compatibility/competing_productivity.lua").read_text(encoding="utf-8")
        runtime = (PLAYER / "runtime/competing_productivity.lua").read_text(encoding="utf-8")
        self.assertNotIn("pairs(technologies)", compatibility)
        self.assertNotIn("pairs(technologies)", compatibility)
        self.assertNotIn("local function copy", compatibility)
        self.assertNotIn("pairs(force.technologies)", runtime)
        self.assertNotIn("research.catalogue", runtime)
        self.assertNotIn("prototypes.", runtime)
        self.assertNotIn("require(", runtime[runtime.index("function M.on_init"):])
        self.assertNotRegex(runtime, r"\.level\s*=(?!=)")
        self.assertNotRegex(runtime, r"\.researched\s*=(?!=)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve()))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0]])

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
FIXED_FACTS_PATH = ROOT / "tests/mir5/fixtures/competing-fixed-f200-sa-captured-facts.json"

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

# The four fixed F200 Space Age providers were captured independently from
# their upstream, prefer-MIR, and prefer-foreign arms in run 40009033780.
# This is authored test expectation, not a projection of the candidate.
FIXED_EXPECTED = (
    ("basic-plate-productivity", 1, "advanced-material-processing", ("copper-plate", "iron-plate"),
     (("recipe-prod-research_copper-1", ("copper-plate",)), ("recipe-prod-research_iron-1", ("iron-plate",))), True),
    ("electric-circuit-productivity", 1, "automation-2", ("electronic-circuit",),
     (("recipe-prod-research_electronic_circuit-1", ("electronic-circuit",)),), True),
    ("advanced-circuit-productivity", 1, "chemical-science-pack", ("advanced-circuit",),
     (("recipe-prod-research_advanced_circuit-1", ("advanced-circuit",)),), True),
    ("automation-science-productivity-4", 4, "automation-science-productivity-3", ("automation-science-pack",),
     (("recipe-prod-research_science_pack_productivity-1", ("automation-science-pack",)),), False),
    ("logistic-science-productivity-4", 4, "logistic-science-productivity-3", ("logistic-science-pack",),
     (("recipe-prod-research_science_pack_productivity-1", ("logistic-science-pack",)),), False),
    ("military-science-productivity-4", 4, "military-science-productivity-3", ("military-science-pack",),
     (("recipe-prod-research_science_pack_productivity-1", ("military-science-pack",)),), False),
    ("chemical-science-productivity-4", 4, "chemical-science-productivity-3", ("chemical-science-pack",),
     (("recipe-prod-research_science_pack_productivity-1", ("chemical-science-pack",)),), False),
    ("production-science-productivity-4", 4, "production-science-productivity-3", ("production-science-pack",),
     (("recipe-prod-research_science_pack_productivity-1", ("production-science-pack",)),), False),
    ("utility-science-productivity-4", 4, "utility-science-productivity-3", ("utility-science-pack",),
     (("recipe-prod-research_science_pack_productivity-1", ("utility-science-pack",)),), False),
    ("space-science-productivity-4", 4, "space-science-productivity-3", ("space-science-pack",),
     (("recipe-prod-research_science_pack_productivity-1", ("space-science-pack",)),), False),
    ("metallurgic-science-productivity-4", 4, "metallurgic-science-productivity-3", ("metallurgic-science-pack",),
     (("recipe-prod-research_science_pack_productivity-1", ("metallurgic-science-pack",)),), False),
    ("electromagnetic-science-productivity-4", 4, "electromagnetic-science-productivity-3", ("electromagnetic-science-pack",),
     (("recipe-prod-research_science_pack_productivity-1", ("electromagnetic-science-pack",)),), False),
    ("agricultural-science-productivity-4", 4, "agricultural-science-productivity-3", ("agricultural-science-pack",),
     (("recipe-prod-research_science_pack_productivity-1", ("agricultural-science-pack",)),), False),
    ("cryogenic-science-productivity-4", 4, "cryogenic-science-productivity-3", ("cryogenic-science-pack",),
     (("recipe-prod-research_science_pack_productivity-1", ("cryogenic-science-pack",)),), False),
    ("promethium-science-productivity-4", 4, "promethium-science-productivity-3", ("promethium-science-pack",),
     (("recipe-prod-research_science_pack_productivity-1", ("promethium-science-pack",)),), False),
    ("bioflux-productivity", 1, "bioflux", ("bioflux",),
     (("recipe-prod-research_bioflux-1", ("bioflux",)),), True),
    ("fish-breeding-productivity", 1, "fish-breeding", ("fish-breeding",),
     (("recipe-prod-research_breeding-1", ("fish-breeding",)),), True),
)

FIXED_ARCHIVES = {
    "plates": ("plates-n-circuit-productivity_0.0.2.zip",
               "E7CC206A847C24E213A0E51568C5A4B00D399F21FF4E84A3A124347D0FF7119F"),
    "science-packs": ("Science_packs_productivity_0.0.1.zip",
                      "5E77A37884000B0DEBCD690F3489C4E69EA80DA4A924498940C34FD718AF92EC"),
    "bioflux": ("bioflux-productivity_0.1.0.zip",
                "84B3A23218E596A4585AD405F8586E18DCA9C8B493EA77CE8EE90584C180F1AE"),
    "fish": ("fish-productivity_1.0.0.zip",
             "1B19C53C06A0BF0E9FE40C38C8755F3917B6BEECEBD3355439BD65980C45C1FB"),
}


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
          function fixed_active()
            return {base="2.0.77", ["space-age"]="2.0.77",
              ["plates-n-circuit-productivity"]="0.0.2", Science_packs_productivity="0.0.1",
              ["bioflux-productivity"]="0.1.0", ["fish-productivity"]="1.0.0"}
          end
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
                    prototype={enabled=true, level=1, max_level=4294967295, effects={}}}
                  force.technologies[replacement.id] = target
                end
                add_effects(target.prototype.effects, replacement.effects)
              end
            end
            return force
          end
          function install_competing(preference, force, selected_mods)
            local target = require("platform.target")
            target.id, target.factorio_version = "f200", "2.0"
            script = {active_mods=selected_mods or exact_active()}
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

    def fixed_contract(self):
        return self.lua.execute('return require("compatibility.competing_productivity").select(fixed_active(), f200_target())')

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

          -- The same named callback composition loads for a fixed F200 Space
          -- Age provider; its row ID is irrelevant to bootstrap dispatch.
          local prior_init = calls.on_init
          handlers = {events={}}
          remote={interfaces={},add_interface=function(name, value) remote.interfaces[name]=value end}
          script = {active_mods={["fish-productivity"]="1.0.0"}, on_init=function(f) handlers.init=f end,
            on_configuration_changed=function(f) handlers.configuration=f end, on_load=function(f) handlers.load=f end,
            on_event=function(id, f) handlers.events[id]=f end, on_nth_tick=function() end}
          package.loaded["runtime.bootstrap"] = nil
          local fixed_provider = require("runtime.bootstrap")
          fixed_provider.register()
          handlers.init()
          assert(calls.on_init == prior_init + 1)

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

    def test_fixed_f200_space_age_inventory_and_selection_are_explicit(self):
        facts = json.loads(FIXED_FACTS_PATH.read_text(encoding="utf-8"))
        self.assertEqual(1, facts["schema"])
        self.assertEqual("MIR5FixedCompetingF200SANativeReferenceFactsV1", facts["kind"])
        self.assertEqual(40009033780, facts["run"])
        expected_by_provider = {
            "plates": FIXED_EXPECTED[:3],
            "science-packs": FIXED_EXPECTED[3:15],
            "bioflux": FIXED_EXPECTED[15:16],
            "fish": FIXED_EXPECTED[16:],
        }
        self.assertEqual(set(expected_by_provider), {provider["key"] for provider in facts["providers"]})
        self.assertEqual(17, sum(len(rows) for rows in expected_by_provider.values()))

        for provider in facts["providers"]:
            self.assertEqual(FIXED_ARCHIVES[provider["key"]],
                             (provider["archive"], provider["archive_sha256"]))
            rows = expected_by_provider[provider["key"]]
            upstream = provider["arms"]["upstream"]["provider_rows"]
            published = provider["arms"]["published"]
            foreign = provider["arms"]["foreign"]
            self.assertEqual({row[0] for row in rows}, set(provider["published_removed_ids"]))
            self.assertEqual([], provider["foreign_changed_provider_ids"])
            self.assertTrue({row[0] for row in rows}.issubset(upstream))
            self.assertTrue(set(upstream).issubset(foreign["provider_rows"]))
            self.assertEqual({name for name, row in published["provider_rows"].items() if row is None},
                             {row[0] for row in rows})
            for name, first_level, predecessor, recipes, replacements, initial in rows:
                row = upstream[name]
                self.assertIn(predecessor, row["prerequisites"])
                self.assertEqual(recipes, tuple(effect["recipe"] for effect in row["effects"]))
                self.assertTrue(all(effect["change"] == 0.1 for effect in row["effects"]))
                self.assertNotIn("level", row)
                self.assertEqual(row, foreign["provider_rows"][name])
                if initial:
                    self.assertNotRegex(name, r"-\d+$")
                    self.assertEqual(1, first_level)
                else:
                    self.assertTrue(name.endswith("-4"))
                    self.assertEqual(f"{name[:-1]}3", predecessor)
                    self.assertEqual(4, first_level)
                for replacement, required_recipes in replacements:
                    self.assertIn(replacement, published["mir_rows"])
                    effects = published["mir_rows"][replacement]["effects"]
                    actual_recipes = {effect["recipe"] for effect in effects
                                      if effect["type"] == "change-recipe-productivity"}
                    self.assertTrue(set(required_recipes).issubset(actual_recipes))

        contract = plain(self.fixed_contract())
        actual = tuple(
            (item["id"], item["first_level"], item["predecessor"],
             tuple(effect["recipe"] for effect in item["effects"]),
             tuple((replacement["id"], tuple(effect["recipe"] for effect in replacement["effects"]))
                   for replacement in item["replacements"]), item["initial_retirement"])
            for item in contract["bindings"]
        )
        self.assertEqual(FIXED_EXPECTED, actual)
        self.assertEqual(
            ("plates-n-circuit-productivity", "Science_packs_productivity", "bioflux-productivity", "fish-productivity"),
            tuple(provider["name"] for provider in contract["providers"]),
        )

        self.lua.execute(r'''
          local binding = require("compatibility.competing_productivity")
          local target = f200_target()
          assert(binding.select({base="2.0.77", ["space-age"]="2.0.77",
            ["plates-n-circuit-productivity"]="0.0.3"}, target) == nil)
          assert(binding.select({base="2.0.77", ["plates-n-circuit-productivity"]="0.0.2"}, target) == nil)
          assert(binding.select({base="2.0.77", ["space-age"]="2.0.77",
            ExpandedProductivityResearch="1.3.8", ["fish-productivity"]="1.0.0"}, target) == nil)
          assert(binding.select(fixed_active(), {id="f210", factorio_version="2.1"}) == nil)
        ''')

    def test_fixed_f200_space_age_runtime_preserves_foreign_rows_and_partial_work(self):
        self.lua.execute(r'''
          local binding = require("compatibility.competing_productivity")
          local active = fixed_active()
          local contract = binding.select(active, f200_target())
          local function owned(name)
            local state = storage.mir_competing_productivity
            return state and state.owned_disabled[71] and state.owned_disabled[71][name] or nil
          end

          -- All four exact fixed providers compose. Initial identities are
          -- retired only when untouched; level-four tails retain levels 1--3.
          local force = force_from_contract(contract)
          storage = {}
          local runtime = install_competing(true, force, active)
          runtime.on_init()
          for _, item in ipairs(contract.bindings) do
            local technology = force.technologies[item.id]
            assert(technology.enabled == false and technology.visible_when_disabled == true, item.id)
            assert(owned(item.id).disabled == true, item.id)
            assert(technology.level == item.first_level and technology.researched == false, item.id)
          end
          runtime = install_competing(false, force, active)
          runtime.on_configuration_changed()
          for _, item in ipairs(contract.bindings) do
            local technology = force.technologies[item.id]
            assert(technology.enabled == true and technology.visible_when_disabled == false, item.id)
          end
          assert(storage.mir_competing_productivity == nil)

          -- A foreign pre-disable gets no MIR record, so relaxation cannot
          -- re-enable or reveal it.
          force = force_from_contract(contract)
          force.technologies["bioflux-productivity"].enabled = false
          force.technologies["bioflux-productivity"].visible_when_disabled = false
          storage = {}
          runtime = install_competing(true, force, active)
          runtime.on_init()
          assert(force.technologies["bioflux-productivity"].enabled == false)
          assert(force.technologies["bioflux-productivity"].visible_when_disabled == false)
          assert(owned("bioflux-productivity") == nil)
          runtime = install_competing(false, force, active)
          runtime.on_configuration_changed()
          assert(force.technologies["bioflux-productivity"].enabled == false)
          assert(force.technologies["bioflux-productivity"].visible_when_disabled == false)

          -- Partial MIR coverage and a changed native prerequisite both leave
          -- the matching foreign initial identity untouched.
          force = force_from_contract(contract)
          force.technologies["recipe-prod-research_copper-1"].prototype.effects[1].change = .2
          force.technologies["recipe-prod-research_electronic_circuit-1"].prototype.level = 2
          force.technologies["fish-breeding-productivity"].prototype.prerequisites["fish-breeding"] = nil
          storage = {}
          runtime = install_competing(true, force, active)
          runtime.on_init()
          assert(force.technologies["basic-plate-productivity"].enabled == true)
          assert(force.technologies["electric-circuit-productivity"].enabled == true)
          assert(force.technologies["fish-breeding-productivity"].enabled == true)
          assert(owned("basic-plate-productivity") == nil and owned("electric-circuit-productivity") == nil
            and owned("fish-breeding-productivity") == nil)

          -- If a previously admitted MIR replacement changes, release only
          -- our recorded disablement and leave the provider's row future-open.
          force = force_from_contract(contract)
          storage = {}
          runtime = install_competing(true, force, active)
          runtime.on_init()
          force.technologies["recipe-prod-research_copper-1"].prototype.effects[1].change = .2
          runtime.on_configuration_changed()
          assert(force.technologies["basic-plate-productivity"].enabled == true)
          assert(force.technologies["basic-plate-productivity"].visible_when_disabled == false)
          assert(owned("basic-plate-productivity") == nil)

          -- A queued initial research has live fractional work. It remains
          -- wholly foreign until it is no longer current or queued.
          force = force_from_contract(contract)
          local queued = force.technologies["electric-circuit-productivity"]
          force.current_research, force.research_queue, force.research_progress = queued, {queued}, .27
          storage = {}
          runtime = install_competing(true, force, active)
          runtime.on_init()
          assert(queued.enabled == true and queued.visible_when_disabled == false)
          assert(#force.research_queue == 1 and force.research_queue[1] == queued)
          assert(force.current_research == queued and force.research_progress == .27)
          assert(owned("electric-circuit-productivity") == nil)

          -- Detached partial work remains foreign even without a queue entry.
          -- Only a known empty native saved-progress slot permits retirement.
          for _, saved in ipairs({.27, -.1, "invalid", false}) do
            force = force_from_contract(contract)
            local paused = force.technologies["electric-circuit-productivity"]
            paused.saved_progress = saved
            storage = {}
            runtime = install_competing(true, force, active)
            runtime.on_init()
            assert(paused.enabled == true and paused.visible_when_disabled == false)
            assert(paused.saved_progress == saved and owned(paused.name) == nil)
          end
          force = force_from_contract(contract)
          force.technologies["electric-circuit-productivity"].saved_progress = 0
          storage = {}
          runtime = install_competing(true, force, active)
          runtime.on_init()
          assert(force.technologies["electric-circuit-productivity"].enabled == false)

          -- A completed initial level is foreign credit. The cap path retires
          -- only the next level and never rewrites the earned level flag.
          force = force_from_contract(contract)
          local earned = force.technologies["advanced-circuit-productivity"]
          earned.level, earned.researched = 2, false
          storage = {}
          runtime = install_competing(true, force, active)
          runtime.on_init()
          assert(earned.level == 2 and earned.researched == false)
          assert(earned.enabled == false and earned.visible_when_disabled == true)
          assert(owned("advanced-circuit-productivity").disabled == true)
        ''')

    def test_data_preference_preserves_ids_and_matches_captured_remaining_recipe_effects(self):
        facts = json.loads(FIXED_FACTS_PATH.read_text(encoding="utf-8"))
        def lua(value):
            if isinstance(value, dict):
                return self.lua.table_from({key: lua(item) for key, item in value.items()})
            if isinstance(value, list):
                return self.lua.table_from([lua(item) for item in value])
            return value
        def effects(row):
            return [dict(row["effects"][i]) for i in range(1, len(row["effects"]) + 1)]
        adapter = self.lua.eval('require("compatibility.competing_productivity")')
        for provider in facts["providers"]:
            with self.subTest(provider=provider["key"]):
                archive_name = provider["archive"][:-4]
                mod, version = archive_name.rsplit("_", 1)
                active = lua({"base": "2.0.77", "space-age": "2.0.77", mod: version})
                rows = provider["arms"]["published"]["mir_rows"]
                raw = lua({"technology": provider["arms"]["upstream"]["provider_rows"]})
                self.lua.eval('function(raw) setmetatable(raw.technology, {__pairs=function() error("foreign scan") end}) end')(raw)
                owned = lua(list(rows.values()))
                adapter.retain_foreign_coverage(owned, raw, active, lua({"id":"f200", "factorio_version":"2.0"}), False)
                for index in range(1, len(owned) + 1):
                    row = owned[index]
                    original = rows[row["name"]]
                    expected = provider["foreign_remaining_mir_rows"][row["name"]]
                    self.assertEqual([] if expected is None else expected["effects"], effects(row))
                    self.assertEqual(original["level"], row["level"])
                    self.assertEqual(original["unit"]["count_formula"], row["unit"]["count_formula"])
                    self.assertEqual(original["max_level"], row["max_level"])
                    if not effects(row):
                        self.assertFalse(row["enabled"])
                for name, original in provider["arms"]["upstream"]["provider_rows"].items():
                    self.assertEqual(original["effects"], effects(raw["technology"][name]))
                preferred = lua(list(rows.values()))
                adapter.retain_foreign_coverage(preferred, raw, active, lua({"id":"f200", "factorio_version":"2.0"}), True)
                for index in range(1, len(preferred) + 1):
                    self.assertEqual(rows[preferred[index]["name"]]["effects"], effects(preferred[index]))

    def test_data_incomplete_or_tuned_replacement_keeps_foreign_overlap_exclusive(self):
        self.lua.execute(r'''
          local binding = require("compatibility.competing_productivity")
          local active = {base="2.0.77", ["space-age"]="2.0.77", ["plates-n-circuit-productivity"]="0.0.2"}
          local function attempt(change, foreign_change, disabled)
            local native={type="technology", name="basic-plate-productivity", max_level="infinite",
              prerequisites={"advanced-material-processing"}, enabled=not disabled,
              effects={{type="change-recipe-productivity",recipe="iron-plate",change=foreign_change},
                {type="change-recipe-productivity",recipe="copper-plate",change=foreign_change}}}
            local row={type="technology",name="recipe-prod-research_iron-1",level=1,max_level="infinite",
              effects={{type="change-recipe-productivity",recipe="iron-plate",change=change},
                {type="change-recipe-productivity",recipe="casting-iron",change=change}}, sentinel=17}
            local raw={technology={ [native.name]=native }}
            binding.retain_foreign_coverage({row},raw,active,f200_target(),true)
            assert(native.effects[1].change == foreign_change and native.enabled == not disabled)
            assert(row.sentinel == 17)
            return row
          end
          -- Copper's absent MIR replacement prevents retiring the joint
          -- foreign row, so only iron casting remains eligible for MIR.
          local row=attempt(.1,.1,false)
          assert(#row.effects==1 and row.effects[1].recipe=="casting-iron")
          row=attempt(.2,.1,false)
          assert(#row.effects==1 and row.effects[1].recipe=="casting-iron" and row.effects[1].change==.2)
          row=attempt(.1,.2,false)
          assert(#row.effects==1 and row.effects[1].recipe=="casting-iron")
          row=attempt(.1,.1,true)
          assert(#row.effects==2, "disabled foreign research cannot block future MIR coverage")
        ''')

    def test_source_stays_fixed_and_non_scanning(self):
        compatibility = (PLAYER / "compatibility/competing_productivity.lua").read_text(encoding="utf-8")
        runtime = (PLAYER / "runtime/competing_productivity.lua").read_text(encoding="utf-8")
        self.assertNotRegex(compatibility, r"\bpairs\s*\(\s*technologies\s*\)")
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

"""Independent F200 Space Age plus BobTech combined-profile admission control.

The historical 4.7.20003 capture is kept as a complete oracle in a compact
fixture.  The finite F200 selector adopts established current Base/Space Age
semantics only where this test lists the intentional differences; it does not
reconstruct a profile by scanning installed mods or reuse candidate output as
an expectation.
"""

import argparse
from copy import deepcopy
import gzip
import hashlib
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "source"
ORACLE = ROOT / "tests/fixtures/bob-angel-f200-combined-published-473-expectations.json.gz"
ORACLE_SHA256 = "B80EDB79ABE75F3A19A3D7BD2B9CAB43343807D405C9E474E93219D542EDE633"
ANALYSIS_SHA256 = "38581F4D614DAA251F9208205B49D5F7F8FD697084A40AD266A0EC7117EB44CA"
PROFILE = ROOT / "tests/profiles/bob-angel-full-space-age-f200-2077.json"
PROFILE_SHA256 = "61CBE6299DD2708079EA80FB3871AC980C6FF7281DD126C61B3126A7FF294857"
CONTEXT = ROOT / "tests/fixtures/bob-angel-f200-combined-upstream-context.json.gz"
CONTEXT_SHA256 = "C5B76C07B66A305099412E2BDBD63855234692C9D5DFF32B3351D0A100A75C7D"

# These are the reviewed current-MIR5 Base/Space Age differences from the
# published oracle.  They are policy inputs to this control, not values read
# from generated candidate rows.  All unlisted rows retain the historical
# multiplicity for this finite source-stage admission check.
ADOPTED_EFFECT_MULTIPLICITY = {
    "laser-shooting-speed-8": 1,
    "recipe-prod-research_carbon-1": 3,
    "recipe-prod-research_lubricant_productivity-1": 4,
    "recipe-prod-research_oil_processing_productivity-1": 4,
    "recipe-prod-research_plastic-1": 2,
    "recipe-prod-research_steel-1": 3,
    "recipe-prod-research_sulfur-1": 5,
    "recipe-prod-research_sulfuric_acid_productivity-1": 3,
    "recipe-prod-research_tungsten-1": 3,
}

COMBINED_DELTA = {
    "research_armor_components": {
        "science": "science_automation_logistic_chemical_production_military_metallurgic_space",
        "effects": [{"recipe": "bob-mech-armor-plate", "scale": 0.4}],
    },
    "research_plastic": {
        "science": "science_automation_logistic_chemical_production_agricultural",
        "effects": [{"recipe": "angels-solid-plastic", "scale": 1}],
    },
    "research_steel": {
        "science": "science_automation_logistic_chemical_production",
        "effects": [
            {"recipe": "angels-plate-steel", "scale": 1},
            {"recipe": "angels-plate-steel-2", "scale": 1},
        ],
    },
}

# These detached hidden rows are independently owned by the existing native
# credit and legacy-module-credit contracts.  They are not part of the public
# F200 combined-profile comparison below: keeping the exact fixed identities
# here makes a leaked public row or a newly discovered carrier fail closed.
NATIVE_CREDIT_DESCRIPTORS = (
    ("research_copper", "copper-plate"),
    ("research_iron", "iron-plate"),
    ("research_breeding", "fish-breeding"),
    ("research_oil_processing_productivity", "advanced-oil-processing"),
    ("research_oil_processing_productivity", "basic-oil-processing"),
    ("research_oil_processing_productivity", "coal-liquefaction"),
    ("research_bullets", "firearm-magazine"),
    ("research_grenades", "grenade"),
    ("research_lubricant_productivity", "lubricant"),
    ("research_breeding", "pentapod-egg"),
    ("research_concrete", "stone-brick"),
    ("research_sulfuric_acid_productivity", "sulfuric-acid"),
)
SEPARATE_CARRIER_IDS = {
    f"mir-native-credit-{family}-{recipe}-{direction}"
    for family, recipe in NATIVE_CREDIT_DESCRIPTORS
    for direction in ("positive", "negative")
} | {
    "mir-legacy-module-credit-speed-module",
    "mir-legacy-module-credit-productivity-module",
    "mir-legacy-module-credit-efficiency-module",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def canonical_sha256(row: object) -> str:
    text = json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest().upper()


def plain(value):
    if hasattr(value, "keys"):
        keys = list(value.keys())
        if keys and all(isinstance(key, int) and key >= 1 for key in keys) and set(keys) == set(range(1, len(keys) + 1)):
            return [plain(value[index]) for index in range(1, len(keys) + 1)]
        return {key: plain(value[key]) for key in keys}
    if isinstance(value, (list, tuple)):
        return [plain(row) for row in value]
    return value


def lua_value(lua, value):
    if isinstance(value, dict):
        return lua.table_from({key: lua_value(lua, item) for key, item in value.items()})
    if isinstance(value, list):
        return lua.table_from([lua_value(lua, item) for item in value])
    return value


def pcall_pair(value):
    return value if isinstance(value, tuple) else (value, None)


class BobAngelF200CombinedProfileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if sha256(ORACLE) != ORACLE_SHA256:
            raise AssertionError("combined F200 published oracle changed")
        cls.oracle = json.loads(gzip.decompress(ORACLE.read_bytes()).decode("utf-8"))
        source = cls.oracle["source_analysis"]
        if source["sha256"] != ANALYSIS_SHA256 or source["status"] != "offline-proposal-only":
            raise AssertionError("combined F200 oracle lost its frozen analysis provenance")
        if sha256(PROFILE) != PROFILE_SHA256:
            raise AssertionError("combined F200 source profile changed")
        if sha256(CONTEXT) != CONTEXT_SHA256:
            raise AssertionError("combined F200 NoMIR upstream context changed")
        cls.context = json.loads(gzip.decompress(CONTEXT.read_bytes()).decode("utf-8"))
        if (cls.context.get("schema"), cls.context.get("kind")) != (
            1, "MIR5BobAngelF200CombinedUpstreamDataFinalContextV1"
        ):
            raise AssertionError("combined F200 upstream context schema changed")
        if cls.context["source"] != {
            "capture": "EAD7 control-without-mir",
            "path": str(Path(r"D:/Projects/Factorio/more-infinite-research/build/qualification/whole-product-heavy-space-age-f200-admission-r01-controller/native-captures/control-without-mir/write-data/script-output/data-raw-dump.json")),
            "bytes": 64158857,
            "sha256": "AD702CC98FA30A672C8A358305D0F562A5965E51F28CED8D0EFC8ABD26F5F487",
            "engine_sha256": "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B",
        }:
            raise AssertionError("combined F200 context lost its exact NoMIR source binding")
        if "more-infinite-research" in cls.context["profile"]["selection"]:
            raise AssertionError("combined F200 context must not consume candidate selection")
        cls.mods = {
            row["name"]: row["version"]
            for row in json.loads(PROFILE.read_text(encoding="utf-8"))["mods"]
            if row["enabled"]
        }
        cls.old_mods = {
            row["name"]: row["version"]
            for row in json.loads((ROOT / "tests/profiles/bob-angel-f200-2077.json").read_text(encoding="utf-8"))["mods"]
            if row["enabled"]
        }

    def data_final_stage(self, raw=None, mods=None, expect_failure=False):
        raw = deepcopy(self.context["raw"] if raw is None else raw)
        mods = deepcopy(self.context["profile"]["selection"] if mods is None else mods)
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().source_root = SOURCE.as_posix()
        lua.globals().captured_raw = lua_value(lua, raw)
        lua.globals().active_mods = lua_value(lua, mods)
        lua.execute(r'''
          package.path=source_root.."/?.lua;"..source_root.."/?/init.lua"; package.cpath=""
          mods,script,helpers,log=active_mods,nil,{},function() end
          data={raw=captured_raw}; settings_rows,emitted,technology_publications={},{},0
          function data:extend(rows)
            local published=false
            for _,row in ipairs(rows) do
              self.raw[row.type]=self.raw[row.type] or {}
              assert(self.raw[row.type][row.name]==nil,"duplicate "..row.type..":"..row.name)
              self.raw[row.type][row.name]=row
              if row.setting_type=="startup" then settings_rows[row.name]=row end
              if row.type=="technology" then emitted[row.name]=row; published=true end
            end
            if published then technology_publications=technology_publications+1 end
          end
          local target=require("platform.target")
          target.id,target.factorio_version,target.minimum_base="f200","2.0","2.0.77"
          target.distribution_version,target.cargo_research="5.0.20000",false
          target.recipe_probability,target.receiver_limits,target.productivity_ignores_stats="probability",false,true
          assert(loadfile(source_root.."/settings.lua"))()
          local declared={}
          for name,row in pairs(settings_rows) do declared[name]={value=row.default_value} end
          settings={startup=declared}
          assert(loadfile(source_root.."/data.lua"))()
          emitted,technology_publications={},0
          outcome,message=pcall(function() assert(loadfile(source_root.."/data-final-fixes.lua"))() end)
          if outcome then declared_runtime=require("research.catalogue").declared() end
        ''')
        if expect_failure:
            self.assertFalse(lua.globals().outcome)
        else:
            self.assertTrue(lua.globals().outcome, str(lua.globals().message))
        return lua

    def lua(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().source_root = SOURCE.as_posix()
        lua.execute(r'''
          package.path = source_root .. "/?.lua;" .. source_root .. "/?/init.lua"
          package.cpath = ""
          local target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"
          target.distribution_version, target.cargo_research = "5.0.20000", false
          target.recipe_probability, target.receiver_limits, target.productivity_ignores_stats = "probability", false, true
        ''')
        return lua

    def settings_stage(self):
        lua = self.lua()
        lua.globals().mods = lua.table_from(self.mods)
        lua.execute(r'''
          settings = {startup = {}}; helpers = {}; data = {raw = {}}; emitted = {}
          function data:extend(rows)
            for _, row in ipairs(rows) do
              emitted[row.type] = emitted[row.type] or {}
              assert(emitted[row.type][row.name] == nil, "duplicate setting " .. row.name)
              emitted[row.type][row.name] = row
            end
          end
          assert(loadfile(source_root .. "/settings.lua"))()
        ''')
        return plain(lua.globals().emitted)

    def test_frozen_published_oracle_keeps_complete_rows_effects_labs_and_settings(self):
        technology = self.oracle["technology"]
        rows = technology["added"]
        effects = technology["effect_multiplicity_in_published_order"]
        self.assertEqual(technology["added_count"], 69)
        self.assertEqual(len(rows), 69)
        self.assertEqual(set(rows), set(effects))
        self.assertEqual(len(technology["published_effect_recipe_witnesses"]), 247)
        self.assertEqual(len(technology["published_lab_witnesses"]), 4)
        self.assertEqual(len(technology["published_science_item_witnesses"]), 10)
        self.assertEqual(len(technology["science_vectors_in_published_order"]), 23)
        self.assertEqual(technology["changed"], {})
        self.assertEqual(technology["removed_names"], [])
        self.assertFalse(any("material_" in name for name in rows))
        for name, expected in rows.items():
            self.assertEqual(canonical_sha256(expected["row"]), expected["canonical_sha256"], name)
            self.assertEqual(len(expected["row"]["effects"]), len(effects[name]), name)
        expected_multiplicity = {
            name: len(row["row"]["effects"]) for name, row in rows.items()
        }
        expected_multiplicity.update(ADOPTED_EFFECT_MULTIPLICITY)
        self.assertEqual(set(ADOPTED_EFFECT_MULTIPLICITY) - set(rows), set())
        self.assertEqual(expected_multiplicity["recipe-prod-research_armor_components-1"], 1)
        self.assertEqual(expected_multiplicity["recipe-prod-research_plastic-1"], 2)
        self.assertEqual(expected_multiplicity["recipe-prod-research_steel-1"], 3)
        sections = self.oracle["settings"]["sections"]
        self.assertEqual(sum(len(section["added"]) for section in sections.values()), 875)
        self.assertTrue(all(section["changed"] == {} and section["removed_names"] == []
                            for section in sections.values()))

    def test_named_provider_selector_bypasses_only_the_recognized_legacy_constructors(self):
        lua = self.lua()
        active = lua.table_from(self.mods)
        combined = lua.eval("function(mods) return require('compatibility.bob_angel_f200_combined_profile').select(mods) end")
        self.assertEqual(combined(active), "space-age-bobtech")
        selection = plain(lua.eval("function(mods) return require('compatibility.modern_catalogue').select(mods, {}) end")(active))
        self.assertEqual(selection["profile"], "bob-angel-space-age-bobtech-f200")
        self.assertFalse(selection["bob_angel"])
        self.assertFalse(selection["bob_warfare"])
        self.assertEqual(selection["bob_angel_f200_combined"], "space-age-bobtech")
        self.assertEqual(len(selection["definitions"]), 62)
        self.assertEqual(len(selection["continuations"]), 4)
        self.assertFalse(any(row["key"] == "research_oil_cracking_productivity"
                             for row in selection["definitions"]))
        self.assertFalse(lua.eval("function(mods) return require('compatibility.bob_angel_materials').is_f200_bob_angel(mods) end")(active))

        missing = deepcopy(self.mods)
        del missing["bobtech"]
        self.assertIsNone(combined(lua.table_from(missing)))
        missing_logistics = deepcopy(self.mods)
        del missing_logistics["boblogistics"]
        self.assertIsNone(combined(lua.table_from(missing_logistics)))
        incompatible = deepcopy(self.mods)
        incompatible["Krastorio2"] = "2.1.4"
        self.assertIsNone(combined(lua.table_from(incompatible)))

        old = lua.table_from(self.old_mods)
        self.assertIsNone(combined(old))
        self.assertTrue(lua.eval("function(mods) return require('compatibility.bob_angel_profile').applies(mods) end")(old))
        self.assertTrue(lua.eval("function(mods) return require('compatibility.bob_angel_materials').is_f200_bob_angel(mods) end")(old))
        forbidden = deepcopy(self.old_mods)
        forbidden["space-age"] = "2.0.77"
        ok, message = lua.eval("function(mods) return pcall(function() return require('compatibility.bob_angel_profile').applies(mods) end) end")(lua.table_from(forbidden))
        self.assertFalse(ok)
        self.assertIn("unsupported F200 Bob/Angel saved-profile transition", message)

        # The normal catalogue refuses the incomplete Space Age Bob Warfare
        # profile above. Stub only those independent legacy refusals long
        # enough to observe the continuation filter: absent Bob Logistics
        # must not suppress its two native-owned tails.
        lua.execute("package.loaded['compatibility.bob_angel_profile']={applies=function() return false end};"
                    "package.loaded['compatibility.bob_warfare_profile']={applies=function() return false end}")
        incomplete_continuations = {row["id"] for row in plain(lua.eval(
            "function(mods) return require('compatibility.modern_catalogue').continuations(mods, {}) end"
        )(lua.table_from(missing_logistics)))}
        self.assertIn("inserter-capacity-bonus-8", incomplete_continuations)
        self.assertIn("worker-robots-storage-4", incomplete_continuations)

    def test_settings_keep_all_875_rows_with_only_declared_current_visibility_and_growth_differences(self):
        actual = self.settings_stage()
        sections = self.oracle["settings"]["sections"]
        expected = {}
        for setting_type, section in sections.items():
            expected[setting_type] = {}
            for name, captured in section["added"].items():
                # `targets` is the capture observer's derived diagnostic,
                # absent from Factorio setting prototypes. It is deliberately
                # not smuggled into the player source as a settings snapshot.
                row = deepcopy(captured["row"])
                row.pop("targets", None)
                # The existing MIR5 setting policy keeps unavailable material
                # controls dormant and applies the reviewed growth safety cap.
                # Both are explicit current semantics, not a new F200 profile
                # setting family or a historical-output rewrite.
                if "research_material_" in name:
                    row["hidden"] = True
                if name.startswith(("ips-cost-growth-", "mir-cost-growth-")):
                    row["maximum_value"] = 1000
                expected[setting_type][name] = row
        self.assertEqual(set(actual), set(expected))
        self.assertEqual(sum(len(rows) for rows in actual.values()), 875)
        for setting_type, rows in expected.items():
            self.assertEqual(actual[setting_type], rows, setting_type)

    def test_delta_is_finite_and_preflight_refuses_changed_named_inputs(self):
        lua = self.lua()
        delta = plain(lua.execute("return require('compatibility.modern_catalogue.bob_angel_f200_combined')"))
        additions = {row["key"]: row for row in delta["additions"]}
        self.assertEqual(set(additions), set(COMBINED_DELTA))
        self.assertEqual(delta["omit"], {"research_oil_cracking_productivity": True})
        for key, expected in COMBINED_DELTA.items():
            self.assertEqual(additions[key]["science"], expected["science"], key)
            self.assertEqual(additions[key]["effects"], expected["effects"], key)
            self.assertEqual(additions[key]["tuning"], {
                "base_cost": 8000, "effect_percent": 10, "enabled": True,
                "growth_factor": 2, "linear_increment": 0, "max_level": 0,
                "research_time": 60,
            }, key)
        self.assertFalse(any("material_" in key for key in additions))

        preflight = lua.eval("function(raw) return pcall(function() require('compatibility.modern_catalogue.bob_angel_f200_combined').preflight(raw) end) end")
        raw = deepcopy(self.context["raw"])
        ok, message = pcall_pair(preflight(lua_value(lua, raw)))
        self.assertTrue(ok, message)
        missing = deepcopy(raw)
        del missing["recipe"]["bob-mech-armor-plate"]
        ok, message = pcall_pair(preflight(lua_value(lua, missing)))
        self.assertFalse(ok)
        self.assertIn("missing recipe bob-mech-armor-plate", message)
        changed_owner = deepcopy(raw)
        changed_owner["technology"]["bob-tankotron"]["prerequisites"] = []
        ok, message = pcall_pair(preflight(lua_value(lua, changed_owner)))
        self.assertFalse(ok)
        self.assertIn("armor owner changed", message)
        changed_lab = deepcopy(raw)
        changed_lab["lab"]["bob-lab-alien"]["inputs"] = "not-an-array"
        ok, message = pcall_pair(preflight(lua_value(lua, changed_lab)))
        self.assertFalse(ok)
        self.assertIn("lab inputs changed", message)

    def test_actual_data_final_matches_the_independent_complete_public_contract(self):
        lua = self.data_final_stage()
        emitted = plain(lua.globals().emitted)
        expected = {
            name: captured["row"]
            for name, captured in self.oracle["technology"]["added"].items()
        }
        public = {name: emitted[name] for name in expected}
        self.assertEqual(set(public), set(expected))
        self.assertEqual(public, expected)
        self.assertEqual(set(emitted) - set(expected), SEPARATE_CARRIER_IDS)
        self.assertEqual(lua.globals().technology_publications, 1)
        self.assertNotIn("recipe-prod-research_oil_cracking_productivity-1", public)
        self.assertFalse(any("material_" in name for name in public))

    def test_actual_data_final_refuses_missing_named_recipe_before_publication(self):
        raw = deepcopy(self.context["raw"])
        del raw["recipe"]["bob-mech-armor-plate"]
        lua = self.data_final_stage(raw=raw, expect_failure=True)
        self.assertIn("missing recipe bob-mech-armor-plate", str(lua.globals().message))
        self.assertEqual(plain(lua.globals().emitted), {})
        self.assertEqual(lua.globals().technology_publications, 0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BobAngelF200CombinedProfileTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

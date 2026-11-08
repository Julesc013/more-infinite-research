"""Complete SIF science-policy publication controls over controlled source facts.

The upstream shape is a deliberate host reproduction of SIF's retired white
role, not a captured complete modpack or a native qualification. Run the same
expectations against an extracted player release with --player-root.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest

import test_generator as fixture


ROOT = Path(__file__).resolve().parents[1]
PLAYER = ROOT / "source"
WHITE = "space-science-pack"
POLICIES = (
    "configured", "space", "space-and-promethium", "space-age-progression",
    "official-progression", "mod-progression", "all-official", "all",
)
PAID = json.loads((ROOT / "tests/fixtures/sif-retained-manufacturing/expectations.json").read_bytes())["rows"]


def target_fields(lua, target):
    lua.globals().target_id = target
    lua.execute('''
      local target=require("platform.target")
      target.id,target.factorio_version=target_id,target_id=="f200" and "2.0" or "2.1"
      target.minimum_base=target_id=="f200" and "2.0.77" or "2.1.23"
      target.distribution_version=target_id=="f200" and "5.0.20009" or "5.0.21009"
      target.cargo_research,target.receiver_limits=target_id=="f210",target_id=="f210"
      target.productivity_ignores_stats=true
      target.recipe_probability=target_id=="f200" and "probability" or "independent_probability"
    ''')


class SIFCataloguePolicyTests(unittest.TestCase):
    def inputs(self, target="f210", variant="ordinary", source="retired", sif=True):
        fixture.LuaRuntime = LuaRuntime
        harness = fixture.GeneratorTests()
        harness.setUp()
        target_fields(harness.lua, target)
        engine = "2.0.77" if target == "f200" else "2.1.23"
        mods = {"base": engine, "space-age": engine}
        if sif:
            mods["space-is-fake"] = "1.0.60" if target == "f200" else "1.0.78"
        if variant == "muria":
            mods["Muria"] = "controlled-finite-tail"
        # Reuse the existing complete Generator world for unrelated authored
        # references. Each execution below starts a fresh Lua runtime and uses
        # only the selected player source, including for released-baseline runs.
        raw = fixture.plain_lua(harness.lua.globals().full_world(fixture.lua_table(harness.lua, mods), True)["raw"])
        if target == "f200" and sif:
            for paid in PAID:
                raw["item"][paid["product"]] = {"type": "item", "name": paid["product"]}
                for recipe, owner in paid["recipes"].items():
                    raw["recipe"][recipe] = {
                        "type": "recipe", "name": recipe, "enabled": False,
                        "results": [{"type": "item", "name": paid["product"], "amount": 1}],
                    }
                    row = raw["technology"].setdefault(owner, {
                        "type": "technology", "name": owner, "max_level": "infinite",
                        "unit": {"count_formula": "1000*2^L", "time": 60,
                                 "ingredients": [["automation-science-pack", 1]]},
                        "effects": [],
                    })
                    row["effects"].append({"type": "change-recipe-productivity", "recipe": recipe, "change": .1})
        if sif:
            raw["technology"]["promethium-science-pack"]["prerequisites"] = [
                "agricultural-science-pack", "metallurgic-science-pack",
                "electromagnetic-science-pack", "quantum-processor",
            ] + (["fusion-reactor"] if target == "f200" else [])
            raw["technology"]["quantum-processor"] = {}
        elif target == "f200":
            raw["technology"]["promethium-science-pack"]["prerequisites"] = ["biter-egg-handling", "fusion-reactor"]
        if source != "native":
            # These are the independently retained SIF prerequisite facts;
            # neither MIR's generated rows nor its policy supply this input.
            raw["technology"][WHITE]["prerequisites"] = ["utility-science-pack", "production-science-pack"]
        if source == "replacement":
            raw["recipe"]["controlled-white-producer"] = {
                "type": "recipe", "name": "controlled-white-producer", "enabled": True,
                "ingredients": [["iron-plate", 1]],
                "results": [{"type": "item", "name": WHITE, "amount": 1}],
            }
            raw["item"]["iron-plate"] = {"type": "item", "name": "iron-plate"}
        if variant == "finite-lab":
            for level, count in ((6, 500), (7, 1000)):
                name = f"research-speed-{level}"
                raw["technology"][name] = {
                    "type": "technology", "name": name, "level": level, "max_level": level,
                    "prerequisites": [f"research-speed-{level-1}"],
                    "effects": [{"type": "laboratory-speed", "modifier": .5}],
                    "unit": {"count": count, "time": 45,
                             "ingredients": [["automation-science-pack", 2], [WHITE, 3]]},
                }
        if variant == "muria":
            for level, count in ((7, 1000), (8, 2000)):
                name = f"weapon-shooting-speed-{level}"
                raw["technology"][name] = {
                    "type": "technology", "name": name, "level": level, "max_level": level,
                    "prerequisites": [f"weapon-shooting-speed-{level-1}"],
                    "effects": [{"type": "gun-speed", "ammo_category": category, "modifier": .4}
                                for category in ("bullet", "shotgun-shell")],
                    "unit": {"count": count, "time": 45,
                             "ingredients": [["automation-science-pack", 2], [WHITE, 3]]},
                }
        if variant == "external-weapon":
            raw["technology"]["weapon-shooting-speed-7"] = {
                "type": "technology", "name": "weapon-shooting-speed-7", "level": 7, "max_level": "infinite",
                "prerequisites": ["weapon-shooting-speed-6"],
                "effects": [{"type": "gun-speed", "ammo_category": category, "modifier": .4}
                            for category in ("bullet", "shotgun-shell")],
                "unit": {"count_formula": "1000*2^L", "time": 45, "ingredients": [["automation-science-pack", 2]]},
            }
        return raw, mods

    def stage(self, raw, mods, target, policy="configured", force_gate=False):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = PLAYER.as_posix()
        lua.globals().raw_input = fixture.lua_table(lua, deepcopy(raw))
        lua.globals().mods = fixture.lua_table(lua, mods)
        lua.globals().startup = fixture.lua_table(lua, {
            "mir-science-pack-ingredient-policy": {"value": policy},
            "ips-require-space-gate": {"value": force_gate},
        })
        lua.execute('''
          package.path=player_root.."/?.lua;"..player_root.."/?/init.lua"
          package.cpath=""
          settings,helpers,log={startup=startup},nil,function()end
          data={raw=raw_input};emitted={};technology_publications=0
          function data:extend(rows)
            local technology_batch=false
            for _,row in ipairs(rows) do
              self.raw[row.type]=self.raw[row.type] or {}
              assert(self.raw[row.type][row.name]==nil,"duplicate "..row.name)
              self.raw[row.type][row.name]=row
              if row.type=="technology" then emitted[row.name]=row;technology_batch=true end
            end
            if technology_batch then technology_publications=technology_publications+1 end
          end
        ''')
        target_fields(lua, target)
        lua.execute('''
          assert(loadfile(player_root.."/data.lua"))()
          stage_ok,stage_error=pcall(assert(loadfile(player_root.."/data-final-fixes.lua")))
        ''')
        return lua

    def emitted(self, lua):
        self.assertTrue(lua.globals().stage_ok, lua.globals().stage_error)
        self.assertEqual(1, lua.globals().technology_publications)
        rows = fixture.plain_lua(lua.globals().emitted)
        self.assertIn("recipe-prod-research_gears-1", rows)
        self.assertIn("recipe-prod-research_science_pack_productivity-1", rows)
        return rows

    def test_complete_catalogue_under_all_policies_and_forced_gate(self):
        for target in ("f200", "f210"):
            for policy in POLICIES:
                for gate in (False, True):
                    with self.subTest(target=target, policy=policy, force_gate=gate):
                        retired_raw, mods = self.inputs(target)
                        available_raw, _ = self.inputs(target, source="native")
                        available = self.emitted(self.stage(available_raw, mods, target, policy, gate))
                        retired_lua = self.stage(retired_raw, mods, target, policy, gate)
                        retired = self.emitted(retired_lua)
                        self.assertEqual(set(available), set(retired), "science retirement lost an identity")
                        for name, row in retired.items():
                            expected = deepcopy(available[name])
                            expected["unit"]["ingredients"] = [ingredient for ingredient in expected["unit"]["ingredients"]
                                                                if ingredient[0] != WHITE]
                            if "prerequisites" in expected:
                                expected["prerequisites"] = [gate for gate in expected["prerequisites"] if gate != WHITE] or {}
                            self.assertEqual(expected, row, name)
                            if row.get("enabled") is not False:
                                self.assertNotIn(WHITE, [ingredient[0] for ingredient in row["unit"]["ingredients"]], name)
                                self.assertNotIn(WHITE, row.get("prerequisites", []), name)
                        self.assertEqual(retired_raw["technology"][WHITE],
                                         fixture.plain_lua(retired_lua.globals().data.raw.technology[WHITE]))

    def test_relocated_and_retained_native_owners_use_the_same_final_policy(self):
        for target, variant, continuation in (
            ("f200", "finite-lab", "research-speed-8"),
            ("f210", "finite-lab", "research-speed-8"),
            ("f210", "muria", "weapon-shooting-speed-9"),
            ("f210", "external-weapon", "research-speed-7"),
        ):
            for policy in ("configured", "all"):
                with self.subTest(target=target, variant=variant, policy=policy):
                    raw, mods = self.inputs(target, variant)
                    lua = self.stage(raw, mods, target, policy)
                    rows = self.emitted(lua)
                    self.assertIn(continuation, rows)
                    self.assertIsNot(rows[continuation].get("enabled"), False)
                    for name, row in rows.items():
                        if row.get("enabled") is not False:
                            self.assertNotIn(WHITE, [ingredient[0] for ingredient in row["unit"]["ingredients"]], name)
                            self.assertNotIn(WHITE, row.get("prerequisites", []), name)
                    for name in ("research-speed-6", "research-speed-7", "weapon-shooting-speed-7", "weapon-shooting-speed-8"):
                        if name in raw["technology"]:
                            self.assertEqual(raw["technology"][name], fixture.plain_lua(lua.globals().data.raw.technology[name]), name)
                    if variant == "external-weapon":
                        self.assertNotIn("weapon-shooting-speed-7", rows)

    def test_worker_robot_cargo_size_provider_ends_after_its_actual_tail_and_uses_final_sif_science(self):
        """WorkerRobotCargoSizeResearch 1.0.0 shape: finite 4..max, optional infinite max+1."""
        upstream_science = [
            ["automation-science-pack", 1], ["logistic-science-pack", 1],
            ["chemical-science-pack", 1], ["production-science-pack", 1],
            ["utility-science-pack", 1], [WHITE, 1],
        ]

        def install_provider(raw, maximum, infinite):
            # The upstream chain begins after Base's finite level three.  The
            # controlled world supplies its own normalised level-three row, so
            # retain the actual finite predecessor shape the adapter consumes.
            raw["technology"]["worker-robots-storage-3"] = {
                "type": "technology", "name": "worker-robots-storage-3",
                "effects": [{"type": "worker-robot-storage", "modifier": 1}],
                "prerequisites": ["worker-robots-storage-2"],
                "unit": {"count": 450, "ingredients": [["automation-science-pack", 1]], "time": 60},
                "upgrade": True,
            }
            provider = {}
            for level in range(4, maximum + 1):
                provider[f"worker-robots-storage-{level}"] = {
                    "type": "technology", "name": f"worker-robots-storage-{level}",
                    "effects": [{"type": "worker-robot-storage", "modifier": 1}],
                    "prerequisites": (["worker-robots-storage-3", WHITE] if level == 4
                                      else [f"worker-robots-storage-{level - 1}"]),
                    "unit": {"count": 2 ** (level - 4) * 1000, "ingredients": deepcopy(upstream_science),
                             "time": 60},
                    "upgrade": True,
                }
            if infinite:
                level = maximum + 1
                provider[f"worker-robots-storage-{level}"] = {
                    "type": "technology", "name": f"worker-robots-storage-{level}",
                    "effects": [{"type": "worker-robot-storage", "modifier": 1}],
                    "prerequisites": [f"worker-robots-storage-{level - 1}"],
                    "unit": {"count_formula": "2^(L - 4)*1000", "ingredients": deepcopy(upstream_science),
                             "time": 60},
                    "max_level": "infinite", "upgrade": True,
                }
            raw["technology"].update(provider)
            return provider

        for maximum, infinite in ((4, False), (7, False), (10, False),
                                  (4, True), (7, True), (10, True)):
            for policy in ("configured", "all"):
                with self.subTest(maximum=maximum, infinite=infinite, policy=policy):
                    retired_raw, mods = self.inputs("f210")
                    available_raw, _ = self.inputs("f210", source="native")
                    mods["WorkerRobotCargoSizeResearch"] = "1.0.0"
                    retired_provider = install_provider(retired_raw, maximum, infinite)
                    available_provider = install_provider(available_raw, maximum, infinite)
                    retired_lua = self.stage(retired_raw, mods, "f210", policy)
                    available_lua = self.stage(available_raw, mods, "f210", policy)
                    retired, available = self.emitted(retired_lua), self.emitted(available_lua)
                    continuation = f"worker-robots-storage-{maximum + 1}"
                    for name, expected in retired_provider.items():
                        self.assertEqual(expected, fixture.plain_lua(retired_lua.globals().data.raw.technology[name]), name)
                    for name, expected in available_provider.items():
                        self.assertEqual(expected, fixture.plain_lua(available_lua.globals().data.raw.technology[name]), name)
                    if infinite:
                        self.assertNotIn(continuation, retired)
                        self.assertNotIn(continuation, available)
                        continue
                    self.assertIn(continuation, retired)
                    self.assertIn(continuation, available)
                    expected = deepcopy(available[continuation])
                    expected["unit"]["ingredients"] = [
                        ingredient for ingredient in expected["unit"]["ingredients"] if ingredient[0] != WHITE
                    ]
                    expected["prerequisites"] = [
                        prerequisite for prerequisite in expected.get("prerequisites", []) if prerequisite != WHITE
                    ]
                    self.assertEqual(expected, retired[continuation])
                    self.assertNotIn(WHITE, [ingredient[0] for ingredient in retired[continuation]["unit"]["ingredients"]])
                    self.assertNotIn(WHITE, retired[continuation].get("prerequisites", []))
                    self.assertIn(f"worker-robots-storage-{maximum}", retired[continuation]["prerequisites"])

    def test_usable_white_and_absent_sif_do_not_retire_science(self):
        for source, sif in (("native", True), ("replacement", True), ("native", False)):
            for target in ("f200", "f210"):
                with self.subTest(target=target, source=source, sif=sif):
                    raw, mods = self.inputs(target, source=source, sif=sif)
                    rows = self.emitted(self.stage(raw, mods, target, "all"))
                    for name in ("research-speed-7", "weapon-shooting-speed-7", "recipe-prod-research_gears-1"):
                        self.assertIsNot(rows[name].get("enabled"), False)
                        self.assertIn(WHITE, [ingredient[0] for ingredient in rows[name]["unit"]["ingredients"]], name)

    def test_malformed_source_is_not_a_retirement_success(self):
        for defect in ("recipe-type", "owner-type", "recipe-difficulty"):
            with self.subTest(defect=defect):
                raw, mods = self.inputs()
                if defect == "recipe-type":
                    raw["recipe"][WHITE] = "invalid"
                elif defect == "owner-type":
                    raw["technology"][WHITE] = "invalid"
                else:
                    raw["recipe"][WHITE]["normal"] = "invalid"
                lua = self.stage(raw, mods, "f210")
                self.assertFalse(lua.globals().stage_ok)
                self.assertIn("MIR SIF science source: malformed", lua.globals().stage_error)
                self.assertEqual(0, lua.globals().technology_publications)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    parser.add_argument("--player-root", type=Path, default=PLAYER)
    args = parser.parse_args()
    PLAYER = args.player_root.resolve(strict=True)
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(SIFCataloguePolicyTests))
    raise SystemExit(not result.wasSuccessful())

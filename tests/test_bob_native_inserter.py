"""Independent F210 Bob Logistics native inserter-owner preflight controls."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
PLAYER = ROOT / "source"
FACTS_PATH = ROOT / "tests/fixtures/bob-logistics-f210-native-continuation-facts.json"

CAPTURE_HASHES = {
    "q005-bob-full-base": {
        "upstream": {
            "result_sha256": "A3BDB63E4A02517422180D14AC744475E19820BF63B18F60C42F0FE329B7F04D",
            "data_raw_sha256": "E50A66C38427AE45765564D301085BF42BC17FB904BAF93EB296C4CF4B648D6F",
        },
        "published": {
            "result_sha256": "D2EA633FB74D29192F1C35EB7019A427338E71F5A5C370876D922EFD53C88337",
            "data_raw_sha256": "80462037B1982AF008B845D1389045C69E8D0BF58C0D7BC7A287BD4B4FC4024F",
        },
    },
    "q006-bob-full-space-age": {
        "upstream": {
            "result_sha256": "54E06C838AD8F53F6D28DFBCE20B7228EAD446AA3CC366304CFA411AC4A67CDF",
            "data_raw_sha256": "9850830424454DE5760C3CE0DB2A6D0055875339DE40B80EC08433E288EAFE2A",
        },
        "published": {
            "result_sha256": "37E78B8C197BC7BCBEC3554C0C234C39BD910B686C0B107FC710678F0160FACB",
            "data_raw_sha256": "0419DF1FD2C5495B5BEC692268F30294F1E19C168D199CB9BF4C7569EF20E6A4",
        },
    },
    "q009-bob-angel-full-base": {
        "upstream": {
            "result_sha256": "C48037EE409BCC14BA9686EF55C7C8BB67FB13B688E5738535CBF42F0F989565",
            "data_raw_sha256": "77EAA31B5BA3BC58915E717FD2243BAF1FD6ACFFD9EA9328CC7CFAB8998E1BD3",
        },
        "published": {
            "result_sha256": "C2DEC7D83147410EAB1B9799FE83704F8EB3B7298AFA2085BC0DEBE1ED2760A5",
            "data_raw_sha256": "742447E96872EE100F7ACF1131C16C89631057144E98AA1FBC5CC61C00FF4E55",
        },
    },
}


def _lua_value(lua, value):
    if isinstance(value, dict):
        table = lua.table()
        for key, item in value.items():
            table[key] = _lua_value(lua, item)
        return table
    if isinstance(value, list):
        table = lua.table()
        for index, item in enumerate(value, 1):
            table[index] = _lua_value(lua, item)
        return table
    return value


def _plain(value):
    if not hasattr(value, "items"):
        return value
    items = dict(value.items())
    if items and set(items) == set(range(1, len(items) + 1)):
        return [_plain(items[index]) for index in range(1, len(items) + 1)]
    return {key: _plain(item) for key, item in items.items()}


class BobNativeInserterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS_PATH.read_text(encoding="utf-8"))
        if cls.facts["kind"] != "mir5-f210-bob-logistics-native-continuation-facts":
            raise AssertionError("Bob native inserter facts lost their identity")
        if cls.facts["release_qualification"]:
            raise AssertionError("Bob native inserter capture facts cannot become release evidence")

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = PLAYER.as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
        ''')
        self.adapter = self.lua.execute('return require("compatibility.bob_native_continuations")')

    def owners(self):
        return [
            deepcopy(self.facts["native_technology"]),
            deepcopy(self.facts["worker_storage_native_technology"]),
        ]

    def raw(self, owners=None):
        if owners is None:
            owners = self.owners()
        return _lua_value(self.lua, {"technology": {owner["name"]: owner for owner in owners}})

    def test_captured_native_owner_and_mir4_skip_are_exactly_bound(self):
        owner = self.facts["native_technology"]
        self.assertEqual("inserter-capacity-bonus-8", owner["name"])
        self.assertEqual("infinite", owner["max_level"])
        self.assertEqual(
            ["inserter-stack-size-bonus", "bulk-inserter-capacity-bonus"],
            [effect["type"] for effect in owner["effects"]],
        )
        self.assertEqual([1, 3], [effect["modifier"] for effect in owner["effects"]])
        self.assertEqual("boblogistics_3.0.2.zip", self.facts["native_owner"]["archive"])
        self.assertEqual("boblogistics/data.lua:59", self.facts["native_owner"]["data_entrypoint"])
        self.assertEqual("boblogistics/prototypes/technology-inserter.lua",
                         self.facts["native_owner"]["source_member"])
        self.assertTrue(self.facts["native_owner"]["unconditionally_authored"])
        worker = self.facts["worker_storage_native_technology"]
        self.assertEqual("bob-infinite-worker-robots-storage-4", worker["name"])
        self.assertEqual("infinite", worker["max_level"])
        self.assertEqual([{"type": "worker-robot-storage", "modifier": 1}], worker["effects"])
        self.assertEqual("boblogistics/data.lua:58", self.facts["worker_storage_native_owner"]["data_entrypoint"])
        self.assertEqual("boblogistics/prototypes/technology-logistics.lua",
                         self.facts["worker_storage_native_owner"]["source_member"])
        self.assertEqual(
            {"inserter_capacity_bonus": "inserter-capacity-bonus-8",
             "worker_robots_storage": "bob-infinite-worker-robots-storage-4"},
            self.facts["native_technologies"],
        )
        self.assertEqual(
            ["inserter-capacity-bonus-8", "bob-infinite-worker-robots-storage-4"],
            _plain(self.adapter["native_technologies"]),
        )
        self.assertEqual("already_infinite", self.facts["published_mir4_source_fact"]["already_infinite_disposition"])
        self.assertEqual("competing_infinite_kept",
                         self.facts["published_mir4_worker_storage_owner_fact"]["owner_disposition"])
        self.assertEqual("worker-robots-storage-3",
                         self.facts["published_mir4_worker_storage_owner_fact"]["base_prerequisite"])
        self.assertEqual(3, len(self.facts["capture_provenance"]))
        self.assertEqual(
            {"q005-bob-full-base", "q006-bob-full-space-age", "q009-bob-angel-full-base"},
            {record["id"] for record in self.facts["capture_provenance"]},
        )
        observed = {record["id"]: record for record in self.facts["capture_provenance"]}
        for capture_id, expected in CAPTURE_HASHES.items():
            self.assertEqual(expected, {
                "upstream": {
                    "result_sha256": observed[capture_id]["upstream"]["result_sha256"],
                    "data_raw_sha256": observed[capture_id]["upstream"]["data_raw_sha256"],
                },
                "published": {
                    "result_sha256": observed[capture_id]["published"]["result_sha256"],
                    "data_raw_sha256": observed[capture_id]["published"]["data_raw_sha256"],
                },
            })
        self.assertTrue(all(record["upstream_published_native_owner_equal"]
                            for record in self.facts["capture_provenance"]))
        self.assertTrue(all(record["upstream_published_worker_storage_owner_equal"]
                            for record in self.facts["capture_provenance"]))

    def test_preflight_accepts_the_exact_native_owner_without_mutation(self):
        raw = self.raw()
        before = _plain(raw)
        self.assertTrue(self.adapter["preflight"](raw))
        self.assertEqual(before, _plain(raw))

    def test_preflight_rejects_missing_or_finite_owner_without_mutation(self):
        no_technology = _lua_value(self.lua, {})
        before_no_technology = _plain(no_technology)
        with self.assertRaisesRegex(Exception, "requires data.raw.technology"):
            self.adapter["preflight"](no_technology)
        self.assertEqual(before_no_technology, _plain(no_technology))

        for name in self.adapter["native_technologies"].values():
            with self.subTest(owner=name):
                missing_owners = self.owners()
                missing_owners = [owner for owner in missing_owners if owner["name"] != name]
                missing = self.raw(missing_owners)
                before_missing = _plain(missing)
                with self.assertRaisesRegex(Exception, f"missing {name}"):
                    self.adapter["preflight"](missing)
                self.assertEqual(before_missing, _plain(missing))

                finite_owners = self.owners()
                next(owner for owner in finite_owners if owner["name"] == name)["max_level"] = 8
                finite = self.raw(finite_owners)
                before_finite = _plain(finite)
                with self.assertRaisesRegex(Exception, f"requires infinite {name}"):
                    self.adapter["preflight"](finite)
                self.assertEqual(before_finite, _plain(finite))

    def test_preflight_tolerates_unconsumed_native_fields_without_mutation(self):
        changed = self.owners()
        for owner in changed:
            owner["icons"] = [{"icon": "__reskin__/alternate.png", "icon_size": 64}]
            owner["effects"] = [{"type": "foreign-effect", "modifier": 999}]
            owner["prerequisites"] = ["foreign-prerequisite"]
            owner["unit"] = {"count_formula": "foreign", "time": 1, "ingredients": [["foreign-pack", 9]]}
            owner["foreign_unconsumed_marker"] = {"nested": [1, 2, 3]}
        raw = self.raw(changed)
        before = _plain(raw)
        self.assertTrue(self.adapter["preflight"](raw))
        self.assertEqual(before, _plain(raw))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BobNativeInserterTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)

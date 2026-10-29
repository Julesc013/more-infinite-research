"""Host-only activity-observer controls; no native or performance verdict."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/large-factory-activity"


class ActivityFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
function activity_fixture(path, base, surface_count)
  local callbacks, reports, logs, reads = {}, {}, {}, {counts=0, flows=0, samples=0}
  local source = {production=100, products=7, valid=true, engine=base, blocked=false}
  local function readonly(backing)
    return setmetatable({}, {__index=backing,
      __newindex=function() error("native mutation") end})
  end
  local machine = readonly(setmetatable({}, {__index=function(_, key)
    if key == "valid" then return source.valid end
    if key == "products_finished" then return source.products end
    error("unexpected entity read: " .. tostring(key))
  end}))
  local force
  local statistics = readonly({get_input_count=function(name)
    assert(type(name) == "string", "normal quality must remain explicit")
    reads.flows = reads.flows + 1
    return source.production
  end})
  force = readonly({valid=true, index=1, name="player",
    get_item_production_statistics=function(surface)
      assert(surface.valid)
      return statistics
    end})
  local world = {}
  for index=1,surface_count do
    local row = {valid=true, index=index, name="surface-" .. index}
    row.count_entities_filtered=function(filter)
      assert(filter.force == force and type(filter.type) == "string")
      reads.counts = reads.counts + 1
      return 10000
    end
    row.find_entities_filtered=function(filter)
      assert(filter.force == force and filter.type[1] == "assembling-machine"
        and filter.type[2] == "furnace" and filter.limit == 256)
      reads.samples = reads.samples + 1
      local result = {}
      for i=1,(source.oversample and 257 or 1) do result[i] = machine end
      return result
    end
    world[index] = readonly(row)
  end
  -- Factorio's named and indexed aliases must not double count a surface.
  world.nauvis = world[1]
  local mods = {base=base}
  local native_game = readonly({surfaces=world, forces=readonly({player=force})})
  local env = {script={active_mods=mods,
    on_init=function(fn) callbacks.init=fn end,
    on_load=function(fn) callbacks.load=fn end,
    on_configuration_changed=function(fn) callbacks.configuration=fn end,
    on_event=function(id, fn) assert(id==1); callbacks.tick=fn end},
    defines={events={on_tick=1}},
    prototypes={item=setmetatable({}, {__index=function(_, name)
      if name == source.missing then return nil end
      return readonly({})
    end})},
    helpers={table_to_json=function(report)
      reports[#reports+1] = report
      return source.oversize and string.rep("x", 65537) or "{}"
    end},
    log=function(message) logs[#logs+1] = message end}
  env._G=env
  setmetatable(env, {__index=function(_, key)
    if key == "game" then assert(not source.blocked, "illegal game access"); return native_game end
    if key == "storage" or key == "global" or key == "settings" or key == "require" then
      error("forbidden access: " .. key)
    end
    return _G[key]
  end})
  assert(loadfile(path, "t", env))()
  return {callbacks=callbacks, reports=reports, logs=logs, reads=reads, source=source, mods=mods,
    tick=function(value) if callbacks.tick then callbacks.tick{tick=value} end end}
end
''')

    def fixture(self, base="2.0.77", surfaces=1):
        return self.lua.globals().activity_fixture(str(FIXTURE / "control.lua"), base, surfaces)

    def finish(self, instance):
        instance.callbacks.init()
        instance.tick(100)
        for tick in range(101, 700):
            instance.tick(tick)
        self.assertEqual(len(instance.logs), 1)
        instance.tick(700)
        self.assertIsNone(instance.callbacks.tick)
        self.assertEqual(len(instance.logs), 2)
        return instance.reports[2]

    def test_progress_is_observed_without_mutating_native_objects(self):
        for base in ("2.0.77", "2.1.23"):
            with self.subTest(base=base):
                x = self.fixture(base, 2)
                x.callbacks.init()
                x.tick(100)
                x.source.production, x.source.products = 103, 9
                x.tick(700)
                report = x.reports[2]
                self.assertTrue(report.activity_observed)
                self.assertEqual(report.positive_normal_item_input_delta, 90)
                self.assertEqual(report.sampled_products_finished_delta, 4)
                self.assertEqual(report.observed_ticks, 600)
                self.assertEqual(report.metadata.base_version, base)
                self.assertEqual(x.reads.counts, 36)
                self.assertEqual(x.reads.flows, 60)
                self.assertEqual(x.reads.samples, 2)
                self.assertIsNone(x.callbacks.tick)
                before = (x.reads.counts, x.reads.flows, len(x.logs))
                x.tick(701)
                self.assertEqual(before, (x.reads.counts, x.reads.flows, len(x.logs)))

    def test_large_idle_counts_do_not_qualify_activity_or_performance(self):
        report = self.finish(self.fixture())
        self.assertEqual(report.initial[1].entity_counts["assembling-machine"], 10000)
        for key in ("activity_observed", "large_factory_qualified", "performance_acceptance", "release_qualification"):
            self.assertFalse(report[key])

    def test_load_and_configuration_rearm_only_before_updates(self):
        x = self.fixture()
        x.source.blocked = True
        x.callbacks.init()
        x.callbacks.configuration()
        x.callbacks.load()
        self.assertEqual(x.reads.counts, 0)
        self.assertEqual(len(x.logs), 0)
        x.source.blocked = False
        x.tick(100)
        x.tick(700)
        self.assertEqual(len(x.logs), 2)
        x.callbacks.load()
        x.tick(800)
        x.tick(1400)
        self.assertEqual(len(x.logs), 4)

    def test_counter_decrease_and_invalidated_machine_are_not_progress(self):
        x = self.fixture()
        x.callbacks.init()
        x.tick(1)
        x.source.production, x.source.products = 90, 2
        x.tick(601)
        self.assertFalse(x.reports[2].activity_observed)
        self.assertEqual(x.reports[2].normal_item_counter_decreases, 15)
        self.assertEqual(x.reports[2].sampled_product_counter_decreases, 1)
        x.callbacks.load()
        x.tick(700)
        x.source.valid = False
        x.tick(1300)
        self.assertEqual(x.reports[4].invalidated_sampled_machines, 1)
        self.assertFalse(x.reports[4].activity_observed)

    def test_missing_item_is_explicitly_outside_production_sample(self):
        x = self.fixture()
        x.source.missing = "space-science-pack"
        report = self.finish(x)
        self.assertIsNone(report.initial[1].normal_item_inputs["space-science-pack"])
        self.assertEqual(x.reads.flows, 28)

    def test_bounds_and_unexpected_endpoint_refuse_instead_of_completing(self):
        cases = ("engine", "surfaces", "mods", "sample", "counter", "report", "endpoint")
        for case in cases:
            with self.subTest(case=case):
                x = self.fixture("2.0.78" if case == "engine" else "2.0.77", 33 if case == "surfaces" else 1)
                if case == "mods":
                    for i in range(128):
                        x.mods[f"extra-{i}"] = "1.0.0"
                x.source.oversample = case == "sample"
                x.source.oversize = case == "report"
                if case == "counter":
                    x.source.production = float("inf")
                x.callbacks.init()
                with self.assertRaises(LuaError):
                    x.tick(100)
                    if case == "endpoint":
                        x.tick(701)
                self.assertFalse(any("COMPLETE" in x.logs[i] for i in range(1, len(x.logs)+1)))

    def test_metadata_selects_pinned_engines_without_player_source(self):
        for family, engine in (("2.0", "2.0.77"), ("2.1", "2.1.23")):
            metadata = json.loads((FIXTURE / f"info-f{200 if family == '2.0' else 210}.json").read_text())
            self.assertEqual(metadata["factorio_version"], family)
            self.assertEqual(metadata["dependencies"], [f"base = {engine}", "? more-infinite-research"])
        self.assertEqual({p.name for p in FIXTURE.iterdir()}, {"control.lua", "info-f200.json", "info-f210.json", "README.md"})


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", required=True)
    args, remaining = parser.parse_known_args()
    sys.path.insert(0, str(Path(args.lua_runtime_dir).resolve()))
    from lupa.lua52 import LuaRuntime, LuaError
    unittest.main(argv=[sys.argv[0], *remaining])

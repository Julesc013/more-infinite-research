"""Pure Lua 5.2 controls for the bounded, caller-owned MIR 5 Library translations."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LibraryTranslationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          translations = require("runtime.library_translations")

          function scope(player_index, locale, force_index, generation)
            return {
              player_index = player_index,
              locale = locale,
              force_index = force_index,
              generation = generation
            }
          end

          function prepared(player_index, locale, force_index, generation, ids)
            local value = assert(translations.new(scope(player_index, locale, force_index, generation)))
            assert(translations.prepare(value, scope(player_index, locale, force_index, generation), ids))
            return value
          end
        ''')

    def test_two_players_keep_separate_locale_labels(self):
        self.lua.execute('''
          local first_scope, second_scope = scope(1, "en", 1, 0), scope(2, "de", 1, 0)
          local first, second = prepared(1, "en", 1, 0, {"gear"}), prepared(2, "de", 1, 0, {"gear"})
          assert(translations.dispatch(first, first_scope, 0, function() return 11 end).issued == 1)
          assert(translations.dispatch(second, second_scope, 0, function() return 12 end).issued == 1)
          assert(translations.complete(first, first_scope, 11, "Gear").published)
          assert(translations.complete(second, second_scope, 12, "Zahnrad").published)
          assert(translations.labels(first, first_scope).gear == "Gear")
          assert(translations.labels(second, second_scope).gear == "Zahnrad")
          assert(translations.needs_maintenance(first) == false and translations.needs_maintenance(second) == false)
        ''')

    def test_stale_locale_force_and_configuration_callbacks_only_release_slots(self):
        self.lua.execute('''
          local cases = {
            {scope(1, "de", 1, 0), "locale"},
            {scope(1, "en", 2, 0), "force"},
            {scope(1, "en", 1, 1), "configuration"}
          }
          for index, case in ipairs(cases) do
            local original = scope(1, "en", 1, 0)
            local cache = prepared(1, "en", 1, 0, {"gear"})
            local request_id = 100 + index
            assert(translations.dispatch(cache, original, 0, function() return request_id end).issued == 1)
            assert(translations.prepare(cache, case[1], {"gear"}))
            local result = translations.complete(cache, case[1], request_id, "stale-" .. case[2])
            assert(result.released and not result.published)
            local snapshot = assert(translations.snapshot(cache, case[1]))
            assert(snapshot.stats.outstanding == 0 and snapshot.labels.gear == nil)
          end
        ''')

    def test_configuration_reset_preserves_issued_ids_until_callback(self):
        self.lua.execute('''
          local initial, changed = scope(1, "en", 1, 0), scope(1, "en", 1, 1)
          local cache = prepared(1, "en", 1, 0, {"gear"})
          assert(translations.dispatch(cache, initial, 7, function() return 41 end).issued == 1)
          assert(translations.needs_maintenance(cache))
          local ids = {}
          for index = 1, 20 do ids[index] = "current-" .. index end
          assert(translations.prepare(cache, changed, ids))
          assert(translations.snapshot(cache, changed).stats.outstanding == 1)
          -- The retained issued ID consumes one of the same 16 global slots.
          local next_id = 100
          local report = translations.dispatch(cache, changed, 8, function()
            next_id = next_id + 1
            return next_id
          end)
          assert(report.issued == 15 and report.work == 15)
          local stale = translations.complete(cache, changed, 41, "old")
          assert(stale.released and not stale.published)
        ''')

    def test_pending_ledger_round_trip_is_detached_and_contains_only_issued_records(self):
        self.lua.execute('''
          local original = scope(1, "en", 1, 40)
          local cache = prepared(1, "en", 1, 40, {"gear"})
          assert(translations.dispatch(cache, original, 7, function()
            return translations.uint32_max
          end).issued == 1)
          local ledger = assert(translations.export_pending(cache))
          assert(#ledger == 1)
          local record = ledger[1]
          assert(record.request_id == translations.uint32_max and record.key == "gear")
          assert(record.scope.locale == "en" and record.cache_generation == cache.generation
            and record.requested_tick == 7)
          for field in pairs(record) do
            assert(field == "request_id" or field == "key" or field == "scope"
              or field == "cache_generation" or field == "requested_tick")
          end
          assert(record.labels == nil and record.ids == nil and record.retry_queue == nil)

          record.key, record.scope.locale, record.requested_tick = "foreign", "mutated", 8
          local retained = assert(translations.export_pending(cache))[1]
          assert(retained.key == "gear" and retained.scope.locale == "en" and retained.requested_tick == 7)

          -- The caller allocates a new lifetime epoch before a reopened cache
          -- receives the old issued window. It is therefore stale and cannot
          -- publish into the new view.
          local reopened_scope = scope(1, "en", 1, 41)
          local reopened = prepared(1, "en", 1, 41, {"gear"})
          assert(translations.hydrate_pending(reopened, assert(translations.export_pending(cache))))
          assert(translations.snapshot(reopened, reopened_scope).stats.outstanding == 1)
          local exported = assert(translations.export_pending(reopened))
          exported[1].scope.generation = 99
          assert(assert(translations.export_pending(reopened))[1].scope.generation == 40)
        ''')

    def test_pending_same_key_across_catalogue_generations_round_trips(self):
        self.lua.execute('''
          local active = scope(1, "en", 1, 40)
          local cache = prepared(1, "en", 1, 40, {"gear"})
          assert(translations.dispatch(cache, active, 0, function() return 11 end).issued == 1)
          assert(translations.prepare(cache, active, {"gear", "other"}))
          local request_id = 11
          assert(translations.dispatch(cache, active, 1, function()
            request_id = request_id + 1; return request_id
          end).issued == 2)
          local pending = assert(translations.export_pending(cache))
          assert(#pending == 3 and pending[1].key == "gear" and pending[2].key == "gear")
          assert(pending[1].cache_generation ~= pending[2].cache_generation)

          local reopened_scope = scope(1, "en", 1, 41)
          local reopened = prepared(1, "en", 1, 41, {"gear"})
          assert(translations.hydrate_pending(reopened, pending), "own multi-generation export was rejected")
          assert(translations.snapshot(reopened, reopened_scope).stats.outstanding == 3)
          for _, record in ipairs(pending) do
            local result = translations.complete(reopened, reopened_scope, record.request_id, "old")
            assert(result.released and not result.published)
          end
          assert(translations.labels(reopened, reopened_scope).gear == nil)
          assert(translations.dispatch(reopened, reopened_scope, 2, function() return 21 end).issued == 1)
          assert(translations.complete(reopened, reopened_scope, 21, "Gear").published)
          assert(translations.labels(reopened, reopened_scope).gear == "Gear")
        ''')

    def test_repeated_reopen_retains_same_key_from_distinct_scopes(self):
        self.lua.execute('''
          local original_scope = scope(1, "en", 1, 40)
          local original = prepared(1, "en", 1, 40, {"gear"})
          assert(translations.dispatch(original, original_scope, 0, function() return 31 end).issued == 1)
          local second_scope = scope(1, "de", 1, 41)
          local second = prepared(1, "de", 1, 41, {"gear"})
          assert(translations.hydrate_pending(second, assert(translations.export_pending(original))))
          assert(translations.dispatch(second, second_scope, 1, function() return 32 end).issued == 1)
          local pending = assert(translations.export_pending(second))
          assert(#pending == 2 and pending[1].key == pending[2].key)
          assert(pending[1].cache_generation == pending[2].cache_generation,
            "a fresh cache can reuse its local generation; the complete caller scope distinguishes requests")
          local latest_scope = scope(1, "de", 1, 42)
          local latest = prepared(1, "de", 1, 42, {"gear"})
          assert(translations.hydrate_pending(latest, pending), "own multi-scope export was rejected")
          assert(translations.snapshot(latest, latest_scope).stats.outstanding == 2)
          for _, record in ipairs(pending) do
            local result = translations.complete(latest, latest_scope, record.request_id, "stale")
            assert(result.released and not result.published)
          end
          assert(not translations.needs_maintenance(latest))
          assert(translations.dispatch(latest, latest_scope, 2, function() return 33 end).issued == 1)
          assert(translations.complete(latest, latest_scope, 33, "Zahnrad").published)
          assert(translations.labels(latest, latest_scope).gear == "Zahnrad")
        ''')

    def test_pending_ledger_rejects_malformed_duplicate_and_uint32_records_without_mutation(self):
        self.lua.execute('''
          local active = scope(1, "en", 1, 0)
          local function record(id, key, value_scope, generation, tick)
            return {request_id = id, key = key, scope = value_scope or active,
              cache_generation = generation or 1, requested_tick = tick or 0}
          end
          local function reject(ledger)
            local cache = prepared(1, "en", 1, 0, {"gear"})
            local labels, pending, keys = cache.labels, cache.pending_by_id, cache.pending_by_key
            assert(translations.hydrate_pending(cache, ledger) == false)
            assert(cache.outstanding == 0 and next(cache.pending_by_id) == nil and next(cache.pending_by_key) == nil)
            assert(cache.labels == labels and cache.pending_by_id == pending and cache.pending_by_key == keys)
          end

          reject({record(translations.uint32_max + 1, "gear")})
          reject({record(0 / 0, "gear")})
          reject({record(1, string.rep("x", translations.label_limit + 1))})
          reject({record(1, "gear", scope(-1, "en", 1, 0))})
          reject({record(1, "gear", active, 1, math.huge)})
          reject({record(1, "gear"), record(1, "other")})
          reject({record(1, "gear"), record(1, "gear", scope(1, "de", 1, 1), 2)})
          reject({record(1, "gear"), record(2, "gear")})
          local oversized = {}
          for index = 1, translations.outstanding_limit + 1 do oversized[index] = record(index, "key-" .. index) end
          reject(oversized)

          local cache = prepared(1, "en", 1, 0, {"gear"})
          assert(translations.hydrate_pending(cache, {
            record(translations.uint32_max, "gear", active, cache.generation, translations.uint32_max)
          }))
          assert(cache.outstanding == 1 and translations.complete(cache, active,
            translations.uint32_max, "Gear").published)
        ''')

    def test_map_tick_above_uint32_round_trips_dispatch_hydration_and_expiry(self):
        self.lua.execute('''
          local active = scope(1, "en", 1, 0)
          local high_tick = translations.uint32_max + 600
          local cache = prepared(1, "en", 1, 0, {"gear"})
          assert(translations.dispatch(cache, active, high_tick, function() return 17 end).issued == 1)
          local ledger = assert(translations.export_pending(cache))
          assert(ledger[1].requested_tick == high_tick)
          local reopened = prepared(1, "en", 1, 0, {"gear"})
          assert(translations.hydrate_pending(reopened, ledger))
          assert(translations.maintain(reopened, active, high_tick + translations.expiry_ticks).expired == 1)
          assert(translations.snapshot(reopened, active).stats.outstanding == 0)
        ''')

    def test_stale_hydration_reserves_the_window_then_only_releases_on_callback_or_expiry(self):
        self.lua.execute('''
          local old_scope = scope(1, "en", 1, 20)
          local old = prepared(1, "en", 1, 20, {"gear"})
          assert(translations.dispatch(old, old_scope, 0, function() return 41 end).issued == 1)
          local ledger = assert(translations.export_pending(old))

          local current_scope = scope(1, "en", 1, 21)
          local current_ids = {}
          for index = 1, 20 do current_ids[index] = index == 1 and "gear" or "current-" .. index end
          local current = prepared(1, "en", 1, 21, current_ids)
          assert(translations.hydrate_pending(current, ledger))
          local next_id = 100
          assert(translations.dispatch(current, current_scope, 1, function()
            next_id = next_id + 1
            return next_id
          end).issued == 15)
          assert(translations.complete(current, current_scope, 999, "unknown").released == false)
          local stale = translations.complete(current, current_scope, 41, "old Gear")
          assert(stale.released and not stale.published)
          assert(translations.labels(current, current_scope).gear == nil)

          local expiry = prepared(1, "en", 1, 21, {"gear"})
          assert(translations.hydrate_pending(expiry, ledger))
          assert(translations.maintain(expiry, current_scope, translations.expiry_ticks).expired == 1)
          assert(translations.snapshot(expiry, current_scope).stats.outstanding == 0)
          assert(translations.dispatch(expiry, current_scope, translations.expiry_ticks,
            function() return 77 end).issued == 1)
        ''')

    def test_dispatch_label_and_catalogue_bounds(self):
        self.lua.execute('''
          local active = scope(1, "en", 1, 0)
          local ids = {}
          for index = 1, 20 do ids[index] = "item-" .. index end
          local cache = prepared(1, "en", 1, 0, ids)
          local next_id = 0
          local report = translations.dispatch(cache, active, 0, function()
            next_id = next_id + 1
            return next_id
          end)
          assert(report.work == 16 and report.issued == 16)
          assert(translations.snapshot(cache, active).stats.outstanding == 16)
          assert(translations.complete(cache, active, 1, string.rep("a", 1024)).published)
          assert(translations.complete(cache, active, 2, string.rep("b", 1025)).published)
          local snapshot = assert(translations.snapshot(cache, active))
          assert(#snapshot.labels["item-1"] == 1024 and snapshot.labels["item-2"] == nil)
          assert(snapshot.stats.cached_bytes == 1024)

          local too_many = {}
          for index = 1, translations.catalogue_limit + 1 do too_many[index] = "catalogue-" .. index end
          assert(translations.prepare(cache, active, too_many) == false)
          assert(translations.snapshot(cache, active).stats.catalogue_count == 20)

          -- This valid persisted boundary must not admit an additional label.
          cache.cached_bytes = translations.translated_name_byte_limit
          assert(translations.complete(cache, active, 3, "capacity").published)
          assert(translations.labels(cache, active)["item-3"] == nil)
          assert(translations.snapshot(cache, active).stats.cached_bytes == translations.translated_name_byte_limit)
        ''')

    def test_expiry_retries_once_then_uses_stable_id_fallback(self):
        self.lua.execute('''
          local active = scope(1, "en", 1, 0)
          local cache = prepared(1, "en", 1, 0, {"gear"})
          assert(translations.dispatch(cache, active, 0, function() return 1 end).issued == 1)
          assert(translations.needs_maintenance(cache))
          assert(translations.maintain(cache, active, translations.expiry_ticks).expired == 1)
          assert(not translations.needs_maintenance(cache))
          assert(translations.dispatch(cache, active, translations.expiry_ticks, function() return 2 end).issued == 1)
          assert(translations.maintain(cache, active, translations.expiry_ticks * 2).expired == 1)
          local snapshot = assert(translations.snapshot(cache, active))
          assert(snapshot.stats.outstanding == 0 and snapshot.stats.resolved == 1)
          assert(snapshot.stats.fallbacks == 1 and snapshot.labels.gear == nil)
          assert(translations.take_refresh(cache, active))
        ''')

    def test_prepare_and_snapshot_do_not_alias_caller_data(self):
        self.lua.execute('''
          local active = scope(1, "en", 1, 0)
          local ids = {"gear"}
          local cache = assert(translations.new(active))
          assert(translations.prepare(cache, active, ids))
          ids[1] = "foreign"; active.locale = "mutated"; active.generation = 99
          local retained = scope(1, "en", 1, 0)
          assert(translations.dispatch(cache, retained, 0, function() return 8 end).issued == 1)
          assert(translations.complete(cache, retained, 8, "Gear").published)
          local first = assert(translations.snapshot(cache, retained))
          first.scope.locale = "foreign"; first.labels.gear = "foreign"
          local second = assert(translations.snapshot(cache, retained))
          assert(second.scope.locale == "en" and second.labels.gear == "Gear")
          -- labels() is intentionally the cache-owned read-only hot-path map.
          assert(translations.labels(cache, retained).gear == "Gear")
        ''')

    def test_on_load_maintenance_decision_is_read_only(self):
        self.lua.execute('''
          local active = scope(1, "en", 1, 0)
          local cache = assert(translations.new(active))
          local labels, pending, ids = cache.labels, cache.pending_by_id, cache.ids
          assert(not translations.needs_maintenance(cache))
          assert(cache.labels == labels and cache.pending_by_id == pending and cache.ids == ids)
          assert(translations.prepare(cache, active, {"gear"}))
          assert(translations.dispatch(cache, active, 0, function() return 9 end).issued == 1)
          labels, pending, ids = cache.labels, cache.pending_by_id, cache.ids
          assert(translations.needs_maintenance(cache))
          assert(cache.labels == labels and cache.pending_by_id == pending and cache.ids == ids)
        ''')

    def test_component_has_no_runtime_registration_or_host_imports(self):
        source = (ROOT / "source/runtime/library_translations.lua").read_text(encoding="utf-8")
        for forbidden in ("require(", "game.", "storage[", "script.", "remote.", "on_event("):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LibraryTranslationTests))
    sys.exit(0 if result.wasSuccessful() else 1)

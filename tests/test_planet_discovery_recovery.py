"""Focused Lua 5.2 controls for the one-time MIR3.2 space-location recovery."""
import argparse
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PlanetDiscoveryRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          target = {id="f210", distribution_version="5.0.21000"}
          package.loaded["platform.target"] = target
          prototypes = {space_location={nauvis={},fulgora={},gleba={},aquilo={}}}
          unlock_log = {}

          function tech(researched, effects)
            return {researched=researched == true, prototype={effects=effects}}
          end

          function force(name, technologies, unlocked)
            local state = {unlocked=unlocked or {}, unlocks=0, progress=.42}
            local value = {
              valid=true, name=name, technologies=technologies,
              unrelated="keep", research_progress=state.progress,
              reset_technology_effects=function() error("recovery reset technology effects") end,
            }
            function value.is_space_location_unlocked(location)
              return state.unlocked[location] == true
            end
            function value.unlock_space_location(location)
              assert(state.unlocked[location] ~= true, "recovery double-unlocked " .. location)
              state.unlocked[location] = true
              state.unlocks = state.unlocks + 1
              unlock_log[#unlock_log + 1] = name .. ":" .. location
            end
            return value, state
          end

          function event(old_version, new_version)
            return {mod_changes={['more-infinite-research']={old_version=old_version,new_version=new_version}}}
          end

          function load_recovery(id, version)
            target.id, target.distribution_version = id, version
            package.loaded["runtime.planet_discovery_recovery"] = nil
            return require("runtime.planet_discovery_recovery")
          end

          function native_mapping(rows, handles, values)
            local handle = assert(io.tmpfile())
            values[handle] = rows
            handles[#handles + 1] = handle
            return handle
          end
        ''')

    def test_exact_upgrade_repairs_each_missing_researched_location_once_in_deterministic_order(self):
        self.lua.execute(r'''
          local alpha, alpha_state = force("alpha", {
            one=tech(true, {
              {type="unlock-space-location",space_location="nauvis"},
              {type="unlock-space-location",space_location="fulgora"},
              {type="unlock-space-location",space_location="nauvis"},
            }),
            ignored=tech(false, {{type="unlock-space-location",space_location="gleba"}}),
          }, {aquilo=true})
          local zeta, zeta_state = force("zeta", {
            two=tech(true, {{type="unlock-space-location",space_location="gleba"}}),
          })
          game = {forces={zeta=zeta,alpha=alpha}}
          local recovery = load_recovery("f210", "5.0.21000")
          assert(recovery.apply == recovery.on_configuration_changed)
          assert(recovery.on_init == nil and recovery.on_load == nil)
          assert(recovery.apply(event("3.2.0", "5.0.21000")) == 3)
          assert(table.concat(unlock_log, ",") == "alpha:fulgora,alpha:nauvis,zeta:gleba")
          assert(alpha_state.unlocked.aquilo and alpha.unrelated == "keep" and alpha.research_progress == .42)
          assert(zeta_state.unlocked.gleba and zeta.unrelated == "keep" and zeta.research_progress == .42)
          assert(alpha_state.unlocks == 2 and zeta_state.unlocks == 1)
          assert(recovery.on_configuration_changed(event("3.2.0", "5.0.21000")) == 0)
          assert(alpha_state.unlocks == 2 and zeta_state.unlocks == 1)
        ''')

    def test_lua_custom_table_shaped_force_technology_and_location_maps_are_admitted(self):
        self.lua.execute(r'''
          local values = {}
          local handles = {}
          local candidate, state = force("custom", native_mapping({
            location=tech(true, {{type="unlock-space-location",space_location="nauvis"}}),
          }, handles, values))
          game = {forces=native_mapping({custom=candidate}, handles, values)}
          prototypes = {space_location=native_mapping({nauvis={}}, handles, values)}
          local original_metatables = {}
          local custom_table_metatable = {
            __pairs=function(value) return next, values[value], nil end,
            __index=function(value, key) return values[value] and values[value][key] end,
          }
          for _, handle in ipairs(handles) do
            original_metatables[handle] = debug.getmetatable(handle)
            debug.setmetatable(handle, custom_table_metatable)
          end
          local recovery = load_recovery("f210", "5.0.21000")
          assert(recovery.apply(event("3.2.0", "5.0.21000")) == 1)
          assert(state.unlocked.nauvis and state.unlocks == 1)
          for _, handle in ipairs(handles) do
            debug.setmetatable(handle, original_metatables[handle])
            handle:close()
          end
        ''')

    def test_wrong_event_target_or_destination_refuses_before_observing_forces(self):
        self.lua.execute(r'''
          local candidate, state = force("candidate", {
            one=tech(true, {{type="unlock-space-location",space_location="nauvis"}}),
          })
          game = setmetatable({}, {
            __index=function(_, key)
              if key == "forces" then error("recovery inspected forces before admission") end
            end,
          })
          prototypes = setmetatable({}, {
            __index=function(_, key)
              if key == "space_location" then error("recovery inspected locations before admission") end
            end,
          })
          local recovery = load_recovery("f210", "5.0.21000")
          assert(recovery.apply(event("3.1.9", "5.0.21000")) == 0)
          assert(recovery.apply(event("3.2.0", "5.0.21001")) == 0)
          assert(recovery.apply({mod_changes={other={old_version="3.2.0",new_version="5.0.21000"}}}) == 0)
          recovery = load_recovery("f200", "5.0.20000")
          assert(recovery.apply(event("3.2.1", "5.0.20000")) == 0)
          assert(state.unlocks == 0 and candidate.research_progress == .42 and candidate.unrelated == "keep")
        ''')

    def test_unresearched_existing_malformed_and_absent_effects_never_grant_a_location(self):
        self.lua.execute(r'''
          local candidate, state = force("candidate", {
            unearned=tech(false, {{type="unlock-space-location",space_location="nauvis"}}),
            absent=tech(true, {{type="unlock-space-location",space_location="missing"}}),
            malformed=tech(true, {
              false,
              7,
              {type="unlock-space-location",space_location=""},
              {type="unlock-space-location",space_location=7},
              {type="change-recipe-productivity",recipe="iron-plate",change=.1},
            }),
            no_prototype={researched=true},
          })
          local invalid, invalid_state = force("invalid", {
            earned=tech(true, {{type="unlock-space-location",space_location="nauvis"}}),
          })
          invalid.valid = false
          game = {forces={candidate=candidate,invalid=invalid}}
          local recovery = load_recovery("f210", "5.0.21000")
          assert(recovery.apply(event("3.2.1", "5.0.21000")) == 0)
          assert(state.unlocks == 0 and invalid_state.unlocks == 0)
          assert(candidate.research_progress == .42 and candidate.unrelated == "keep")
        ''')

    def test_existing_unlock_is_preserved_without_rewriting_any_other_force_state(self):
        self.lua.execute(r'''
          local candidate, state = force("candidate", {
            one=tech(true, {{type="unlock-space-location",space_location="nauvis"}}),
          }, {nauvis=true})
          game = {forces={candidate=candidate}}
          local recovery = load_recovery("f210", "5.0.21000")
          assert(recovery.on_configuration_changed(event("3.2.1", "5.0.21000")) == 0)
          assert(state.unlocks == 0 and state.unlocked.nauvis)
          assert(candidate.research_progress == .42 and candidate.unrelated == "keep")
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(PlanetDiscoveryRecoveryTests))
    sys.exit(0 if result.wasSuccessful() else 1)

"""Pure controls for dormant, descriptor-bounded native migration-credit accounting."""
import argparse
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
PLAYER = ROOT / "source"


class NativeCreditRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = PLAYER.as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          storage, game = {}, {forces={}}
          native_credit_definitions = require("research.native_credit_definitions")
          native_credits = require("runtime.native_credits")
          descriptors = native_credit_definitions.descriptors()
          UINT32_MAX = 4294967295

          function make_technology(name, prototype, level, researched, enabled)
            local state = {
              name=name, valid=true, prototype=prototype, level=level or 1,
              researched=researched == true, enabled=enabled == true,
              visible_when_disabled=false, writes={level=0, enabled=0},
            }
            local object = {}
            setmetatable(object, {
              __index=state,
              __newindex=function(_, key, value)
                state[key] = value
                if key == "level" then
                  state.writes.level = state.writes.level + 1
                  -- F200 level writes represent research through the preceding level.
                  state.researched = false
                  -- Native F200 setter behavior: setting a carrier level enables it.
                  state.enabled = true
                elseif key == "enabled" then
                  state.writes.enabled = state.writes.enabled + 1
                end
              end,
            })
            return object, state
          end

          function descriptor_for(recipe)
            for _, descriptor in ipairs(descriptors) do
              if descriptor.recipe == recipe then return descriptor end
            end
            error("unknown descriptor " .. tostring(recipe))
          end

          local function main_level(levels, main_id)
            local specified = levels and levels[main_id]
            if type(specified) == "table" then
              return specified.level or 1, specified.researched == true
            end
            return specified or 1, false
          end

          local function rebuild_effects(force, main_id)
            local effects = {}
            for _, descriptor in ipairs(descriptors) do
              if descriptor.main_id == main_id and force._included[descriptor.recipe] ~= false then
                effects[#effects + 1] = {
                  type="change-recipe-productivity", recipe=descriptor.recipe, change=force._scalar[descriptor.recipe]
                }
              end
            end
            force.technologies[main_id].prototype.effects = effects
          end

          function make_force(index, included, levels, offsets, scalar)
            local technologies = setmetatable({}, {
              __pairs=function() error("native credits scanned force technologies") end,
            })
            local force = {
              index=index, valid=true, technologies=technologies, _included=included or {}, _scalar={}, _states={},
              external_bonus=17.25, reset_calls=0,
              reset_technology_effects=function() error("native credits reset force effects") end,
              recipes=setmetatable({}, {__index=function() error("native credits read aggregate recipe bonus") end}),
            }
            local main_seen = {}
            for _, descriptor in ipairs(descriptors) do
              local change = scalar and scalar[descriptor.recipe] or .1
              force._scalar[descriptor.recipe] = change
              if not main_seen[descriptor.main_id] then
                local level, researched = main_level(levels, descriptor.main_id)
                local technology, state = make_technology(descriptor.main_id, {
                  name=descriptor.main_id, level=1, max_level=UINT32_MAX, effects={}
                }, level, researched, true)
                technologies[descriptor.main_id], force._states[descriptor.main_id] = technology, state
                main_seen[descriptor.main_id] = true
              end
              local offset = offsets and offsets[descriptor.recipe] or 0
              local positive_level = 1 + (offset > 0 and offset or 0)
              local negative_level = 1 + (offset < 0 and -offset or 0)
              local positive, positive_state = make_technology(descriptor.positive_id, {
                name=descriptor.positive_id, level=1, max_level=UINT32_MAX, hidden=true, enabled=false,
                visible_when_disabled=false,
                effects={{type="change-recipe-productivity", recipe=descriptor.recipe, change=change}},
              }, positive_level, false, false)
              local negative, negative_state = make_technology(descriptor.negative_id, {
                name=descriptor.negative_id, level=1, max_level=UINT32_MAX, hidden=true, enabled=false,
                visible_when_disabled=false,
                effects={{type="change-recipe-productivity", recipe=descriptor.recipe, change=-change}},
              }, negative_level, false, false)
              technologies[descriptor.positive_id], technologies[descriptor.negative_id] = positive, negative
              force._states[descriptor.positive_id], force._states[descriptor.negative_id] = positive_state, negative_state
            end
            for main_id in pairs(main_seen) do rebuild_effects(force, main_id) end
            return force
          end

          function set_included(force, recipe, value)
            local descriptor = descriptor_for(recipe)
            force._included[recipe] = value
            rebuild_effects(force, descriptor.main_id)
          end

          function ledger(force, recipe)
            local current = storage.mir_native_credits
            return current and current.forces[force.index] and current.forces[force.index][recipe] or nil
          end

          function holder(force, recipe, direction)
            local descriptor = descriptor_for(recipe)
            return force.technologies[direction == "positive" and descriptor.positive_id or descriptor.negative_id]
          end
        ''')

    def test_true_completed_level_one_to_false_writes_one_positive_credit_and_keeps_native_setter_hidden(self):
        self.lua.execute(r'''
          local fish = "fish-breeding"
          local force = make_force(1, {}, {['recipe-prod-research_breeding-1']={level=1, researched=true}}, nil, {[fish]=.025})
          game.forces[force.index] = force
          native_credits.on_init()
          assert(ledger(force, fish).included == true and ledger(force, fish).offset == 0)
          assert(holder(force, fish, "positive").level == 1)

          set_included(force, fish, false)
          native_credits.on_configuration_changed()
          local record, positive, negative = ledger(force, fish), holder(force, fish, "positive"), holder(force, fish, "negative")
          assert(record.included == false and record.offset == 1)
          assert(positive.level == 2 and positive.enabled == false and positive.prototype.enabled == false)
          assert(positive.prototype.effects[1].change == .025 and negative.prototype.effects[1].change == -.025)
          assert(negative.level == 1 and negative.enabled == false)
          assert(force._states[positive.name].writes.level == 1 and force._states[positive.name].writes.enabled == 1)
          assert(force.external_bonus == 17.25 and force.reset_calls == 0)
        ''')

    def test_false_level_two_to_true_writes_one_negative_credit_and_repeats_idempotently(self):
        self.lua.execute(r'''
          local fish = "fish-breeding"
          local force = make_force(1, {[fish]=false}, {['recipe-prod-research_breeding-1']=2})
          game.forces[force.index] = force
          native_credits.on_init()
          assert(ledger(force, fish).included == false and ledger(force, fish).offset == 0)

          set_included(force, fish, true)
          native_credits.on_configuration_changed()
          local record, positive, negative = ledger(force, fish), holder(force, fish, "positive"), holder(force, fish, "negative")
          assert(record.included == true and record.offset == -1)
          assert(positive.level == 1 and negative.level == 2 and negative.enabled == false)
          local writes = force._states[negative.name].writes.level
          native_credits.on_configuration_changed()
          assert(ledger(force, fish).offset == -1 and negative.level == 2)
          assert(force._states[negative.name].writes.level == writes, "idempotent mask repeated a native level write")

          -- A level-one infinite holder can report one completed unit through
          -- researched=true. Its removal still goes through a level write.
          local rounded = make_force(2, {[fish]=false}, {['recipe-prod-research_breeding-1']=2})
          holder(rounded, fish, "positive").researched = true
          game.forces[2] = rounded
          native_credits.on_init()
          assert(ledger(rounded, fish).offset == 1)
          set_included(rounded, fish, true)
          native_credits.on_configuration_changed()
          local rounded_positive = holder(rounded, fish, "positive")
          assert(ledger(rounded, fish).offset == 0 and rounded_positive.level == 1
            and rounded_positive.researched == false and rounded_positive.enabled == false)
        ''')

    def test_first_observation_uses_native_carriers_without_inventing_a_historic_preference(self):
        self.lua.execute(r'''
          local fish = "fish-breeding"
          local force = make_force(1, {[fish]=false}, {['recipe-prod-research_breeding-1']={level=1, researched=true}}, {[fish]=3})
          game.forces[force.index] = force
          native_credits.on_init()
          local record = ledger(force, fish)
          assert(record.included == false and record.offset == 3)
          assert(holder(force, fish, "positive").level == 4 and holder(force, fish, "negative").level == 1)
          assert(force._states[holder(force, fish, "positive").name].writes.level == 0)
        ''')

    def test_ambiguous_published_first_upgrade_is_blocked_before_baseline_or_native_writes(self):
        self.lua.execute(r'''
          local fish = "fish-breeding"
          local force = make_force(1, {}, {['recipe-prod-research_breeding-1']=2})
          game.forces[force.index] = force
          local event = {mod_startup_settings_changed=true,
            mod_changes={['more-infinite-research']={old_version='4.7.20002', new_version='5.0.20000'}}}
          local positive = holder(force, fish, "positive")
          local ok, message = pcall(native_credits.preflight_legacy_preference_transition, event, true)
          assert(not ok and tostring(message):find("startup settings unchanged", 1, true))
          assert(storage.mir_native_credits == nil and positive.level == 1
            and force._states[positive.name].writes.level == 0,
            "ambiguous first upgrade allocated a ledger or wrote a native holder")

          -- A valid record is checked per force and recipe, not merely by the
          -- presence of a schema-shaped root bucket. A stale carrier offset
          -- cannot be used to bypass the migration block.
          native_credits.on_init()
          local record = ledger(force, fish)
          record.offset = 1
          ok, message = pcall(native_credits.preflight_legacy_preference_transition, event, true)
          assert(not ok and tostring(message):find("startup settings unchanged", 1, true))
          assert(positive.level == 1 and force._states[positive.name].writes.level == 0
            and record.offset == 1, "stale ledger caused a native correction before rejection")

          record.offset = 0
          record.included = not record.included
          ok, message = pcall(native_credits.preflight_legacy_preference_transition, event, true)
          assert(not ok and tostring(message):find("startup settings unchanged", 1, true))
          record.included = not record.included
          ok, message = pcall(native_credits.preflight_legacy_preference_transition, event, true)
          assert(ok, tostring(message))
          assert(positive.level == 1 and force._states[positive.name].writes.level == 0)

          -- All three published F200 4.7 distribution strings share the
          -- absent-setting-history contract; this is not a 4.7.20002-only
          -- exception.
          local earlier = make_force(2, {}, {['recipe-prod-research_breeding-1']=2})
          game.forces[earlier.index] = earlier
          event.mod_changes['more-infinite-research'].old_version = '4.7.20001'
          ok, message = pcall(native_credits.preflight_legacy_preference_transition, event, true)
          assert(not ok and tostring(message):find("startup settings unchanged", 1, true))
        ''')

    def test_473_first_upgrade_keeps_the_history_free_preference_safeguard(self):
        # The inspected 4.7.3 hotfix leaves the published 4.7 runtime and
        # migration producers unchanged. A new patch string cannot establish
        # an old preference that was never recorded in that save.
        self.lua.execute(r'''
          local fish = "fish-breeding"
          for _, included in ipairs({true, false}) do
            storage, game = {}, {forces={}}
            local force = make_force(1, {[fish]=included}, {['recipe-prod-research_breeding-1']=2})
            game.forces[1] = force
            local event = {mod_startup_settings_changed=true,
              mod_changes={['more-infinite-research']={old_version='4.7.20003', new_version='5.0.20000'}}}
            local ok, message = pcall(native_credits.preflight_legacy_preference_transition, event, true)
            assert(not ok and tostring(message):find("startup settings unchanged", 1, true),
              "4.7.3 patch string bypassed the earned-credit ambiguity guard")
            assert(storage.mir_native_credits == nil)
            for _, state in pairs(force._states) do
              assert(state.writes.level == 0 and state.writes.enabled == 0,
                "rejected upgrade changed native research")
            end

            -- A first unchanged-settings observation remains allowed. Once
            -- that valid ledger exists, a later changed-settings event is
            -- no longer an ambiguous history-free first observation.
            event.mod_startup_settings_changed = false
            assert(pcall(native_credits.preflight_legacy_preference_transition, event, true))
            native_credits.on_init()
            event.mod_startup_settings_changed = true
            assert(pcall(native_credits.preflight_legacy_preference_transition, event, true))
          end
        ''')

    def test_legacy_preflight_allows_unearned_or_nonmatching_configuration_events(self):
        self.lua.execute(r'''
          local force = make_force(1)
          game.forces[force.index] = force
          local exact = {mod_startup_settings_changed=true,
            mod_changes={['more-infinite-research']={old_version='4.7.20002', new_version='5.0.20000'}}}
          local ok, message = pcall(native_credits.preflight_legacy_preference_transition, exact, false)
          assert(ok, tostring(message))
          assert(storage.mir_native_credits == nil, "unearned overlap needed no historic ledger")

          local fish = "fish-breeding"
          force.technologies[descriptor_for(fish).main_id].level = 2
          local unchanged = {mod_startup_settings_changed=false,
            mod_changes={['more-infinite-research']={old_version='4.7.20002', new_version='5.0.20000'}}}
          ok, message = pcall(native_credits.preflight_legacy_preference_transition, unchanged, true)
          assert(ok, tostring(message))
          local different = {mod_startup_settings_changed=true,
            mod_changes={['more-infinite-research']={old_version='5.0.20000', new_version='5.0.20001'}}}
          ok, message = pcall(native_credits.preflight_legacy_preference_transition, different, true)
          assert(ok, tostring(message))
          assert(storage.mir_native_credits == nil)
        ''')

    def test_effect_reset_force_boundaries_and_merge_preserve_only_explicit_carrier_state(self):
        self.lua.execute(r'''
          local fish = "fish-breeding"
          local source = make_force(1, {[fish]=false}, {['recipe-prod-research_breeding-1']=3}, {[fish]=1})
          local destination = make_force(2, {[fish]=false}, {['recipe-prod-research_breeding-1']=3}, {[fish]=2})
          game.forces[1], game.forces[2] = source, destination
          native_credits.on_init()
          assert(ledger(destination, fish).offset == 2)
          local positive, negative = holder(destination, fish, "positive"), holder(destination, fish, "negative")
          positive.enabled, negative.enabled = true, true
          local before_positive, before_negative = positive.level, negative.level
          native_credits.on_technology_effects_reset({force=destination})
          assert(positive.enabled == false and negative.enabled == false)
          assert(positive.level == before_positive and negative.level == before_negative and ledger(destination, fish).offset == 2)

          local positive_writes = destination._states[positive.name].writes.level
          ledger(destination, fish).offset = 1 -- stale pre-merge ledger must not win over native holders.
          game.forces[source.index] = nil
          native_credits.on_forces_merged({source_index=source.index, destination=destination})
          assert(storage.mir_native_credits.forces[source.index] == nil)
          assert(ledger(destination, fish).included == false and ledger(destination, fish).offset == 2)
          assert(destination._states[positive.name].writes.level == positive_writes, "merge overwrote actual holder counts")

          ledger(destination, fish).offset = -9 -- force.reset clears historic accounting, then observes native holders.
          native_credits.on_force_reset({force=destination})
          assert(ledger(destination, fish).offset == 2 and positive.enabled == false and negative.enabled == false)

          local created = make_force(3, {[fish]=false}, {['recipe-prod-research_breeding-1']=2}, {[fish]=-1})
          game.forces[created.index] = created
          native_credits.on_force_created({force=created})
          assert(ledger(created, fish).included == false and ledger(created, fish).offset == -1)
        ''')

    def test_malformed_or_missing_named_rows_retain_prior_rights_without_mutation(self):
        self.lua.execute(r'''
          local fish = "fish-breeding"
          local force = make_force(1, {}, {['recipe-prod-research_breeding-1']=2})
          game.forces[force.index] = force
          native_credits.on_init()
          local positive = holder(force, fish, "positive")
          set_included(force, fish, false)
          positive.prototype.effects[1].change = .2
          native_credits.on_configuration_changed()
          assert(ledger(force, fish).included == true and ledger(force, fish).offset == 0)
          assert(positive.level == 1 and force._states[positive.name].writes.level == 0)

          positive.prototype.effects[1].change = .1
          force.technologies[descriptor_for(fish).main_id] = nil
          native_credits.on_configuration_changed()
          assert(ledger(force, fish).included == true and ledger(force, fish).offset == 0)

          storage.mir_native_credits.forces[force.index][fish] = {included="broken", offset=0}
          local ok, message = pcall(native_credits.on_configuration_changed)
          assert(not ok and tostring(message):find("unsupported native credit record", 1, true))
          assert(positive.level == 1, "malformed ledger mutated a holder before rejection")
          storage.mir_native_credits.forces[force.index][fish] = {included=true, offset=math.huge}
          ok, message = pcall(native_credits.on_configuration_changed)
          assert(not ok and tostring(message):find("unsupported native credit record", 1, true))
        ''')

    def test_native_force_collection_userdata_is_iterated_at_configuration_boundaries(self):
        self.lua.globals().native_forces = object()
        self.lua.execute(r'''
          local force = make_force(1)
          local original_pairs = pairs
          assert(type(native_forces) == "userdata")
          pairs = function(value)
            if value == native_forces then return original_pairs({[1]=force}) end
            return original_pairs(value)
          end
          game.forces = native_forces
          native_credits.on_init()
          local fish = "fish-breeding"
          assert(ledger(force, fish).included == true)
          local descriptor = descriptor_for(fish)
          force.technologies[descriptor.main_id].level = 2
          set_included(force, fish, false)
          native_credits.on_configuration_changed()
          assert(ledger(force, fish).offset == 1)
          assert(force.technologies[descriptor.positive_id].level == 2)
        ''')

    def test_on_load_is_read_only_and_source_stays_descriptor_bounded(self):
        self.lua.execute(r'''
          local force = make_force(1)
          game.forces[1] = force
          native_credits.on_init()
          local retained = storage.mir_native_credits
          game, storage = nil, {sentinel=true}
          native_credits.on_load()
          assert(storage.sentinel == true)
          game, storage = {forces={[1]=force}}, retained
        ''')
        source = (PLAYER / "runtime/native_credits.lua").read_text(encoding="utf-8")
        self.assertIn('require("research.native_credit_definitions")', source)
        self.assertNotIn("Generator", source)
        self.assertNotIn("on_research", source)
        self.assertNotIn("on_tick", source)
        self.assertNotIn("reset_technology_effects", source)
        self.assertNotIn("productivity_bonus", source)
        self.assertNotIn("pairs(force.technologies)", source)
        self.assertNotIn("pairs(prototypes", source)
        self.assertIn("prototype.hidden ~= true", source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(NativeCreditRuntimeTests)
    )
    raise SystemExit(0 if result.wasSuccessful() else 1)

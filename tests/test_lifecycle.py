"""Pure Lua 5.2 controls for MIR 5 lifecycle wiring, not native evidence."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""

          function technology(name, level, enabled)
            return {name = name, level = level, researched = false,
              enabled = enabled ~= false, visible_when_disabled = false,
              prototype = {enabled = true}}
          end

          function force(index, technologies, queue, current, progress)
            local value = {valid = true, index = index, technologies = technologies,
              _queue = queue or {}, current_research = current, research_progress = progress,
              cancelled = 0}
            value.cancel_current_research = function()
              value.cancelled = value.cancelled + 1
              value.current_research = nil
              value.research_progress = nil
              value._queue = {}
            end
            return setmetatable(value, {
              __index = function(self, key)
                if key == "research_queue" then return rawget(self, "_queue") end
                return rawget(self, key)
              end,
              __newindex = function(self, key, replacement)
                if key ~= "research_queue" then rawset(self, key, replacement); return end
                rawset(self, "_queue", replacement)
                local current_research = rawget(self, "current_research")
                local retained = false
                for _, item in ipairs(replacement) do
                  if item == current_research then retained = true; break end
                end
                if not retained then
                  rawset(self, "current_research", replacement[1])
                  rawset(self, "research_progress", replacement[1] and 0 or nil)
                end
              end
            })
          end

          function startup_values(raw_cap, profile, worker_cap)
            return {
              ["ips-max-level-research_gears"] = {value = raw_cap},
              ["ips-enable-research_gears"] = {value = true},
              ["ips-cost-base-research_gears"] = {value = 8000},
              ["ips-cost-linear-increment-research_gears"] = {value = 0},
              ["ips-cost-growth-research_gears"] = {value = 2},
              ["ips-research-time-research_gears"] = {value = 60},
              ["ips-effect-per-level-research_gears"] = {value = 10},
              ["mir-max-level-worker-robots-speed"] = {value = worker_cap or 0},
              ["mir-settings-profile-import"] = {value = profile or ""}
            }
          end

          function boot(forces, raw_cap, profile, saved_storage, retained_handlers, worker_cap, active_mods,
              agriculture_cap, extra_caps, recipe_caps)
            storage = saved_storage or {}
            settings = {startup = startup_values(raw_cap, profile, worker_cap)}
            if agriculture_cap ~= nil then
              settings.startup["ips-max-level-research_agricultural_growth_speed"] = {value = agriculture_cap}
            end
            for name, value in pairs(extra_caps or {}) do settings.startup[name] = {value = value} end
            decoded_profiles = 0
            helpers = {
              json_to_table = function(_) decoded_profiles = decoded_profiles + 1
                return {schema = 1, kind = "mir-settings-profile", settings = {
                  ["ips-max-level-research_gears"] = 10
                }}
              end,
              decode_string = function(value) return value end,
              encode_string = function(value) return value end
            }
            logs = {}
            log = function(message) logs[#logs + 1] = message end
            game = {forces = forces, difficulty_settings = {spoil_time_modifier = 1}}
            -- Factorio exposes `prototypes` only in game-available calls.
            -- A false test value models control parsing before that surface
            -- exists; an omitted value models an empty native collection.
            if recipe_caps == false then
              prototypes = nil
            else
              prototypes = {recipe = recipe_caps or {}}
            end
            mods = active_mods or {}
            handlers = retained_handlers or {events = {}}
            handlers.events = handlers.events or {}
            script = {
              active_mods = active_mods or {},
              on_init = function(handler) handlers.init = handler end,
              on_configuration_changed = function(handler) handlers.configuration = handler end,
              on_load = function(handler) handlers.load = handler end,
              on_event = function(id, handler) handlers.events[id] = handler end,
              on_nth_tick = function(interval, handler)
                handlers.nth = handlers.nth or {}
                handlers.nth[interval] = handler
              end
            }
            defines = {events = {
              on_force_created = 1, on_force_reset = 2, on_forces_merged = 3,
              on_research_finished = 4, on_research_started = 5, on_research_cancelled = 6,
              on_research_reversed = 7, on_technology_effects_reset = 8
            }}
            remote = {interfaces = {}, removed = false}
            remote.add_interface = function(name, functions) remote.interfaces[name] = functions end
            remote.remove_interface = function(_) remote.removed = true end
            package.loaded["control"] = nil
            package.loaded["runtime.bootstrap"] = nil
            package.loaded["runtime.library"] = nil
            package.loaded["runtime.lifecycle"] = nil
            package.loaded["runtime.configuration"] = nil
            -- Each boot models a fresh native control stage. Startup settings
            -- capture that stage's mod profile; do not reuse a Base instance
            -- while testing a subsequent K2 stage in the same host Lua VM.
            package.loaded["research.settings"] = nil
            package.loaded["research.catalogue"] = nil
            control = require("control")
          end
        ''')

    def test_bob_angel_stages_use_named_effective_recipe_caps_without_losing_earned_levels(self):
        self.lua.execute('''
          local target = require("platform.target")
          target.id, target.factorio_version, target.cargo_research = "f200", "2.0", false
          local active = {
            base="2.0.77", angelsbioprocessing="2.0.3", angelsbioprocessinggraphics="2.0.0",
            angelspetrochem="2.0.3", angelspetrochemgraphics="2.0.1",
            angelsrefining="2.0.4", angelsrefininggraphics="2.0.0",
            angelssmelting="2.0.5", angelssmeltinggraphics="2.0.0",
            bobelectronics="2.1.1", boblibrary="2.1.0", bobores="2.1.2",
            bobplates="2.1.1", bobrevamp="2.1.1",
          }
          local family = "research_material_aluminium"
          local early_id, late_id = "recipe-prod-" .. family .. "-1", "recipe-prod-" .. family .. "-4"
          local named_routes = {
            research_material_aluminium = {"angels-plate-aluminium", "angels-plate-aluminium-2"},
            research_material_copper_tungsten = {"bob-copper-tungsten-alloy"},
            research_material_gold = {"angels-plate-gold", "angels-plate-gold-2", "angels-wire-gold-2"},
            research_material_tin = {"angels-plate-tin", "angels-plate-tin-2"},
            research_material_titanium = {"angels-plate-titanium", "angels-plate-titanium-2"},
          }
          local function native_recipe_caps(first, second)
            local values = {}
            for _, routes in pairs(named_routes) do
              for _, name in ipairs(routes) do values[name] = {maximum_productivity=3} end
            end
            values["angels-plate-aluminium"] = {maximum_productivity=first}
            values["angels-plate-aluminium-2"] = {maximum_productivity=second}
            local reads = 0
            return setmetatable({}, {
              __index=function(_, name) reads = reads + 1; return values[name] end,
              __pairs=function() error("lifecycle scanned recipe prototypes") end,
            }), function() return reads end
          end
          -- Each native cap table is deliberately non-enumerable. Lifecycle
          -- may read declared recipe names but must not scan the foreign
          -- recipe catalogue or reconstruct recycling policy.
          local scenarios = {
            -- The selected 125% global prototype cap wins over the authored
            -- default: ceil(1.25 / .02) = 63.
            {percent=2, user=0, expected=63, earned=64, first=1.25, second=1.25},
            -- A technology remains useful until every effect is capped. The
            -- first named route has 400% and the second 200%, so its cap is
            -- max(ceil(4/.02), ceil(2/.02)) = 200 rather than 100.
            {percent=2, user=0, expected=200, earned=201, first=4, second=2},
            -- Explicit user caps remain an upper bound after native caps.
            {percent=2, user=2, expected=2, earned=3, first=4, second=2},
            {percent=2, user=40, expected=40, earned=41, first=4, second=2},
          }
          for _, scenario in ipairs(scenarios) do
            local early, late = technology(early_id, 3, true), technology(late_id, scenario.earned, true)
            early.researched, early.prototype.max_level = true, 3
            local sentinel = technology("foreign-earned", 72, false)
            local player = force(1, {[early_id]=early, [late_id]=late, [sentinel.name]=sentinel})
            local recipe_caps, recipe_reads = native_recipe_caps(scenario.first, scenario.second)
            boot({player}, 0, nil, nil, nil, 0, active, nil, {
              ["ips-effect-per-level-" .. family]=scenario.percent,
              ["ips-max-level-" .. family]=scenario.user,
            }, recipe_caps)
            local limits = require("runtime.lifecycle").cap_limits(player)
            assert(limits[early_id] == scenario.expected and limits[late_id] == scenario.expected)
            assert(recipe_reads() == 2, "lifecycle did not cache the named native recipe caps")
            local declared = require("research.catalogue").declared()
            local material_count = 0
            local seen_families = {}
            for _, row in ipairs(declared) do
              if row.productivity_ceiling then
                material_count = material_count + 1
                assert(row.productivity_ceiling == 3 and row.ownership_kind == "authored_generated")
                assert(row.cap_setting == "ips-max-level-" .. row.family)
                assert(type(row.productivity_recipes) == "table" and #row.productivity_recipes > 0)
                local expected = named_routes[row.family]
                assert(expected and #expected == #row.productivity_recipes)
                for index, name in ipairs(expected) do assert(row.productivity_recipes[index] == name) end
                seen_families[row.family] = (seen_families[row.family] or 0) + 1
              end
            end
            assert(material_count == 10)
            for key in pairs(named_routes) do assert(seen_families[key] == 2) end
            for _, row in ipairs(declared) do
              if row.id == early_id then
                assert(row.productivity_recipes[1] == "angels-plate-aluminium"
                  and row.productivity_recipes[2] == "angels-plate-aluminium-2"
                  and row.productivity_recipes[3] == nil)
              end
            end
            handlers.init()
            assert(recipe_reads() == 2, "reconciliation re-read immutable native recipe caps")
            assert(late.level == scenario.earned and not late.researched and not late.enabled)
            assert(sentinel.level == 72 and not sentinel.enabled)
            assert(early.researched and early.level == 3)
            -- A new control stage with a higher useful limit restores only
            -- MIR's owned disablement, retaining the already earned level.
            local state = storage
            boot({player}, 0, nil, state, nil, 0, active, nil, {
              ["ips-effect-per-level-" .. family]=0.5,
            }, recipe_caps)
            handlers.configuration({})
            assert(late.enabled and late.level == scenario.earned and not sentinel.enabled)
          end
          assert(package.loaded["compatibility.bob_angel_materials"] == nil)
          assert(package.loaded["research.generator"] == nil)
        ''')

    def test_bob_angel_cap_lookup_requires_native_recipe_prototypes_only_for_that_profile(self):
        self.lua.execute('''
          local target = require("platform.target")
          target.id, target.factorio_version, target.cargo_research = "f200", "2.0", false
          local active = {
            base="2.0.77", angelsbioprocessing="2.0.3", angelsbioprocessinggraphics="2.0.0",
            angelspetrochem="2.0.3", angelspetrochemgraphics="2.0.1",
            angelsrefining="2.0.4", angelsrefininggraphics="2.0.0",
            angelssmelting="2.0.5", angelssmeltinggraphics="2.0.0",
            bobelectronics="2.1.1", boblibrary="2.1.0", bobores="2.1.2",
            bobplates="2.1.1", bobrevamp="2.1.1",
          }
          local family = "research_material_aluminium"
          local id = "recipe-prod-" .. family .. "-1"
          local material = technology(id, 1, true)
          local material_force = force(1, {[id]=material})
          -- Handler registration happens while loading control and must not
          -- inspect a native collection that is available only in callbacks.
          boot({material_force}, 0, nil, nil, nil, 0, active, nil, {
            ["ips-effect-per-level-" .. family]=2,
          }, false)
          local lifecycle = require("runtime.lifecycle")
          assert(lifecycle.caps_active())
          local ok, message = pcall(function() return lifecycle.cap_limits(material_force) end)
          assert(not ok and string.find(message, "missing Factorio 2.0 recipe prototypes", 1, true))

          -- An ordinary finite profile still reconciles a cap without ever
          -- touching `prototypes`: only qualified BA rows need this runtime
          -- native capability.
          local gear = technology("recipe-prod-research_gears-1", 6, true)
          local ordinary_force = force(2, {[gear.name]=gear})
          boot({ordinary_force}, 5)
          prototypes = setmetatable({}, {__index=function() error("ordinary profile read prototypes") end})
          local limits = require("runtime.lifecycle").cap_limits(ordinary_force)
          assert(limits[gear.name] == 5)
          handlers.init()
          assert(gear.enabled == false and gear.level == 6)
        ''')

    def test_unlimited_control_registers_no_cap_handlers_or_storage(self):
        self.lua.execute('''
          boot({}, 0)
          local api = remote.interfaces["more-infinite-research.api.v1"]
          assert(type(api) == "table" and type(api.get_version) == "function"
            and type(api.get_capabilities) == "function" and type(api.get_research) == "function")
          assert(type(handlers.init) == "function" and type(handlers.configuration) == "function"
            and type(handlers.load) == "function")
          -- F210 has native recipe-productivity credit ownership even with
          -- every cap unlimited. Its force/reset callbacks are distinct from
          -- the cap research callbacks, which remain absent.
          for id = 1, 3 do assert(type(handlers.events[id]) == "function") end
          for id = 4, 7 do assert(handlers.events[id] == nil) end
          assert(type(handlers.events[8]) == "function"
            and remote.removed == false and next(storage) == nil)
          handlers.init(); handlers.configuration()
          assert(next(storage) == nil, "unlimited settings allocated cap storage")
          local before = next(storage)
          handlers.load()
          assert(before == next(storage), "on_load initialized or changed storage")
          local fresh = force(40, {}, {}, nil, nil)
          game.forces[40] = fresh
          handlers.events[defines.events.on_force_created]({force = fresh})
          handlers.events[defines.events.on_force_reset]({force = fresh})
          handlers.events[defines.events.on_forces_merged]({source_index = 41, destination = fresh})
          assert(next(storage) == nil, "unlimited force cleanup allocated cap storage")
        ''')

    def test_space_age_caps_have_independent_named_ownership(self):
        self.lua.execute('''
          local name = "recipe-prod-research_agricultural_growth_speed-1"
          local native = technology(name, 3, true)
          local f = force(33, {[name] = native}, {}, nil, nil)
          boot({[33] = f}, 0, "", nil, nil, 0, {['space-age'] = '2.1.23'}, 2)
          handlers.init()
          assert(not native.enabled and native.visible_when_disabled)
          assert(storage.mir_caps.owned_disabled[33][name].disabled == true)
          local saved = storage

          boot({[33] = f}, 0, "", saved, nil, 0, {['space-age'] = '2.1.23'}, 0)
          handlers.configuration()
          assert(native.enabled and not native.visible_when_disabled and storage.mir_caps == nil,
            "unlimited agricultural setting did not restore only its own cap transition")
        ''')

    def test_policy_disabled_generated_prototype_reconciles_only_proven_mir_disablement(self):
        self.lua.execute('''
          local name = "recipe-prod-research_gears-1"
          -- An unlimited save still records the first real enabled-to-disabled
          -- transition for a retained data-policy prototype.
          local policy_disabled = technology(name, 2, true)
          policy_disabled.prototype.enabled = false
          local f = force(34, {[name] = policy_disabled}, {}, nil, nil)
          boot({[34] = f}, 0)
          handlers.init()
          assert(not policy_disabled.enabled and storage.mir_caps.owned_disabled[34][name].disabled,
            "disabled prototype was not reconciled on an unlimited save")
          policy_disabled.prototype.enabled = true
          handlers.configuration()
          assert(policy_disabled.enabled and storage.mir_caps == nil,
            "admitted unlimited prototype did not restore only MIR's write")

          -- A foreign pre-disablement never gains an enablement right, even
          -- while its matching authored prototype is disabled.
          local foreign_disabled = technology(name, 2, false)
          foreign_disabled.prototype.enabled = false
          local foreign_force = force(35, {[name] = foreign_disabled}, {}, nil, nil)
          boot({[35] = foreign_force}, 0)
          handlers.init()
          assert(storage.mir_caps == nil and not foreign_disabled.enabled)
          foreign_disabled.prototype.enabled = true
          handlers.configuration()
          assert(storage.mir_caps == nil and not foreign_disabled.enabled,
            "prototype admission re-enabled foreign disablement")

          -- A finite cap right remains owned while the prototype is disabled;
          -- once it is admitted at a non-over-cap level, normal cap recovery
          -- restores that same recorded right.
          local cap_owned = technology(name, 3, true)
          local capped_force = force(36, {[name] = cap_owned}, {}, nil, nil)
          boot({[36] = capped_force}, 2)
          handlers.init()
          assert(not cap_owned.enabled and storage.mir_caps.owned_disabled[36][name].disabled)
          cap_owned.prototype.enabled = false
          handlers.configuration()
          assert(not cap_owned.enabled and storage.mir_caps.owned_disabled[36][name].disabled,
            "disabled prototype discarded a positive cap's owned right")
          cap_owned.force = capped_force
          handlers.events[defines.events.on_research_reversed]({research = cap_owned})
          assert(not cap_owned.enabled and storage.mir_caps.owned_disabled[36][name].disabled,
            "named research reconciliation discarded disabled-prototype ownership")
          cap_owned.level, cap_owned.prototype.enabled = 2, true
          handlers.configuration()
          assert(cap_owned.enabled and storage.mir_caps == nil,
            "admitted below-cap research did not restore the retained cap right")

          -- No force-enabled disabled prototype means no new durable state.
          local normal = technology(name, 1, true)
          local normal_force = force(37, {[name] = normal}, {}, nil, nil)
          boot({[37] = normal_force}, 0)
          handlers.init(); handlers.configuration()
          assert(storage.mir_caps == nil and normal.enabled,
            "ordinary unlimited technology allocated prototype-disablement state")
        ''')

    def test_inactive_caps_discard_restoration_rights_at_force_boundaries(self):
        for boundary in ("created", "reset", "merged"):
            with self.subTest(boundary=boundary):
                self.lua.globals().boundary = boundary
                self.lua.execute('''
                  local name = "recipe-prod-research_gears-1"
                  local original = technology(name, 2, true)
                  original.prototype.enabled = false
                  local old_force = force(34, {[name] = original}, {}, nil, nil)
                  boot({[34] = old_force}, 0)
                  handlers.init()
                  assert(not require("runtime.lifecycle").caps_active())
                  assert(storage.mir_caps.owned_disabled[34][name].disabled,
                    "fixture did not retain an actual prototype-disablement write")

                  -- A new/reset force's foreign disablement does not inherit
                  -- the old force's restoration right at the same index.
                  local foreign = technology(name, 2, false)
                  foreign.prototype.enabled = false
                  local current = technology("unrelated", 1, true)
                  local replacement = force(34, {[name] = foreign}, {current}, current, .75)
                  if boundary == "merged" then
                    -- The engine retains the destination force's research.
                    local destination = force(35, {}, {}, nil, nil)
                    old_force.valid = false
                    game.forces = {[35] = destination}
                    handlers.events[defines.events.on_forces_merged](
                      {source_index = 34, destination = destination})
                    -- Model later index reuse without a second callback that
                    -- could hide a missing merged-source cleanup.
                    game.forces[34] = replacement
                  else
                    game.forces[34] = replacement
                    local id = boundary == "created" and defines.events.on_force_created
                      or defines.events.on_force_reset
                    handlers.events[id]({force = replacement})
                  end
                  foreign.prototype.enabled = true
                  handlers.configuration()
                  assert(not foreign.enabled,
                    boundary .. " transferred old ownership to foreign disablement")
                  assert(storage.mir_caps == nil, boundary .. " retained stale ownership")
                  assert(replacement.current_research == current
                    and replacement.research_progress == .75
                    and #replacement.research_queue == 1
                    and replacement.research_queue[1] == current,
                    boundary .. " changed unrelated research progress")
                ''')

    def test_full_base_limits_are_precomputed_and_research_callbacks_touch_only_the_named_family(self):
        self.lua.execute('''
          local belt_name, brake_name = "recipe-prod-research_belts-1", "braking-force-8"
          local belts, braking = technology(belt_name, 5, true), technology(brake_name, 8, true)
          local raw, reads = {[belt_name] = belts, [brake_name] = braking}, {}
          local technologies = setmetatable({}, {__index = function(_, name)
            reads[name] = (reads[name] or 0) + 1
            return raw[name]
          end})
          local f = force(43, technologies, {}, nil, nil)
          belts.force, braking.force = f, f
          boot({[43] = f}, 0, "", nil, nil, 0, nil, nil, {
            ["ips-max-level-research_belts"] = 4,
            ["mir-max-level-braking-force"] = 7
          })
          assert(require("runtime.lifecycle").caps_active())
          handlers.init()
          assert(not belts.enabled and belts.visible_when_disabled)
          assert(not braking.enabled and braking.visible_when_disabled)
          local limits = require("runtime.lifecycle").cap_limits(f)
          assert(limits[belt_name] == 4 and limits[brake_name] == 7)
          reads = {}
          belts.level = 4
          handlers.events[defines.events.on_research_reversed]({research = belts})
          assert(belts.enabled and not belts.visible_when_disabled,
            "named family reversal did not restore its owned disablement")
          assert(not braking.enabled and braking.visible_when_disabled,
            "named family callback changed another family")
          assert((reads[brake_name] or 0) == 0,
            "research callback looked up an unrelated authored family")
        ''')

    def test_space_age_native_owner_needs_the_exact_authored_effect_contract(self):
        self.lua.execute('''
          local name = "low-density-structure-productivity"
          local function native_owner(effects)
            local value = technology(name, 3, true)
            value.prototype = {max_level = 4294967295, effects = effects}
            return value
          end
          local exact = native_owner({
            {type = "change-recipe-productivity", recipe = "low-density-structure", change = .1},
            {type = "change-recipe-productivity", recipe = "casting-low-density-structure", change = .1}
          })
          local f = force(44, {[name] = exact}, {}, nil, nil)
          exact.force = f
          boot({[44] = f}, 0, "", nil, nil, 0, {['space-age'] = '2.1.23'}, nil,
            {["ips-max-level-research_low_density_structure"] = 2})
          assert(require("runtime.lifecycle").caps_active())
          handlers.init()
          assert(not exact.enabled and exact.visible_when_disabled)
          assert(storage.mir_caps.owned_disabled[44][name].disabled == true)

          local malformed = native_owner({
            {type = "change-recipe-productivity", recipe = "low-density-structure", change = .1},
            {type = "change-recipe-productivity", recipe = "casting-low-density-structure", change = .2}
          })
          local malformed_force = force(45, {[name] = malformed}, {}, nil, nil)
          malformed.force = malformed_force
          boot({[45] = malformed_force}, 0, "", nil, nil, 0, {['space-age'] = '2.1.23'}, nil,
            {["ips-max-level-research_low_density_structure"] = 2})
          handlers.init()
          assert(malformed.enabled and not malformed.visible_when_disabled and storage.mir_caps == nil,
            "a malformed native owner gained cap ownership")
        ''')

    def test_foreign_interface_collision_fails_without_removing_it(self):
        self.lua.execute('''
          storage = {}; settings = {startup = startup_values(0, "")}
          helpers = {}; game = {forces = {}}
          script = {on_init = function() end, on_configuration_changed = function() end,
            on_load = function() end, on_event = function() end}
          defines = {events = {}}
          local foreign = {}
          remote = {interfaces = {["more-infinite-research.api.v1"] = foreign}, removed = false}
          remote.add_interface = function() error("unexpected replacement") end
          remote.remove_interface = function() remote.removed = true end
          package.loaded["control"] = nil
          package.loaded["runtime.bootstrap"] = nil
          package.loaded["runtime.library"] = nil
          package.loaded["runtime.lifecycle"] = nil
          local ok, message = pcall(require, "control")
          assert(not ok and tostring(message):find("MIR API interface collision", 1, true))
          assert(remote.interfaces["more-infinite-research.api.v1"] == foreign and not remote.removed)
        ''')

    def test_native_owner_custom_effect_tuning_keeps_caps_bound_to_current_values(self):
        self.lua.execute('''
          local name="low-density-structure-productivity"
          local function candidate(change)
            local owner=technology(name,3,true)
            owner.prototype={max_level=4294967295,effects={
              {type="change-recipe-productivity",recipe="low-density-structure",change=change},
              {type="change-recipe-productivity",recipe="casting-low-density-structure",change=change}}}
            local value=force(46,{[name]=owner},{},nil,nil)
            owner.force=value
            return value,owner
          end
          local current,owner=candidate(.2)
          boot({[46]=current},0,"",nil,nil,0,{["space-age"]="2.1.23"},nil,
            {["ips-max-level-research_low_density_structure"]=2,
              ["ips-effect-per-level-research_low_density_structure"]=20})
          handlers.init()
          assert(not owner.enabled and storage.mir_caps.owned_disabled[46][name].disabled)
          owner.level=2
          handlers.events[7]({research=owner})
          assert(owner.enabled and not owner.visible_when_disabled)

          local foreign,unexpected=candidate(.1)
          boot({[46]=foreign},0,"",nil,nil,0,{["space-age"]="2.1.23"},nil,
            {["ips-max-level-research_low_density_structure"]=2,
              ["ips-effect-per-level-research_low_density_structure"]=20})
          handlers.init()
          assert(unexpected.enabled and storage.mir_caps == nil,
            "a stale default effect inherited configured owner cap rights")
        ''')

    def test_profile_cap_is_resolved_once_and_preserves_valid_current_progress(self):
        self.lua.execute('''
          local name = "recipe-prod-research_gears-1"
          local first = technology(name, 10, true)
          local second = technology(name, 11, true)
          local worker_probes = 0
          local f1_technologies = setmetatable({[name] = first}, {
            __index = function(value, key)
              if type(key) == "string" and key:find("worker-robots-speed", 1, true) then
                worker_probes = worker_probes + 1
                error("uncapped worker tail was probed")
              end
              return rawget(value, key)
            end
          })
          local f1 = force(1, f1_technologies, {first, first}, first, .42)
          local f2 = force(2, {[name] = second}, {}, nil, nil)
          first.force = f1
          boot({[1] = f1, [2] = f2}, 0, "{")
          assert(decoded_profiles == 1, "profile was not resolved during control parsing")
          handlers.init()
          handlers.events[defines.events.on_research_started]({research = first})
          handlers.events[defines.events.on_research_started]({research = first})
          assert(decoded_profiles == 1, "profile was decoded during a repeated research event")
          assert(worker_probes == 0, "uncapped worker tail was probed by gear events")
          assert(#f1.research_queue == 1 and f1.current_research == first and f1.research_progress == .42)
          assert(not second.enabled and second.visible_when_disabled and second.level == 11)
          assert(storage.mir_caps.schema == 1 and storage.mir_caps.owned_disabled[2][name].disabled)
          local saved_storage = storage
          local retained_handlers = handlers
          boot({[1] = f1, [2] = f2}, 0, "", saved_storage, retained_handlers)
          for id = 4, 7 do
            assert(handlers.events[id] == nil, "unlimited parse retained cap handler " .. id)
          end
          for id = 1, 3 do
            assert(type(handlers.events[id]) == "function",
              "native-credit force callback was removed by an unlimited cap profile")
          end
          assert(type(handlers.events[8]) == "function",
            "native-credit reset callback was removed by an unlimited cap profile")
          handlers.configuration()
          assert(second.enabled and not second.visible_when_disabled and storage.mir_caps == nil)
          handlers.init()
          assert(storage.mir_caps == nil, "unlimited callbacks allocated cap storage")
        ''')

    def test_research_events_remove_queued_current_and_reject_unresolved_current(self):
        self.lua.execute('''
          local name = "recipe-prod-research_gears-1"
          local gear = technology(name, 11, true)
          local unrelated_first = technology("unrelated-first", 1, true)
          local unrelated_second = technology("unrelated-second", 1, true)
          local f = force(4, {[name] = gear},
            {gear, unrelated_first, unrelated_second}, gear, .65)
          gear.force = f
          unrelated_first.force = f
          unrelated_second.force = f
          boot({[4] = f}, 10)
          handlers.events[defines.events.on_research_started]({research = gear})
          assert(f.cancelled == 0, "lifecycle used cancellation for a queued current research")
          assert(#f.research_queue == 2 and f.research_queue[1] == unrelated_first
            and f.research_queue[2] == unrelated_second, "unrelated queue order changed")
          assert(f.current_research == unrelated_first and f.research_progress == 0,
            "removed current research transferred progress")
          assert(not gear.enabled and gear.level == 11 and gear.researched == false)

          local unresolved = technology(name, 11, true)
          local unresolved_other = technology("unrelated-unresolved", 1, true)
          local f_unresolved = force(5, {[name] = unresolved}, {unresolved_other}, unresolved, .75)
          unresolved.force = f_unresolved
          unresolved_other.force = f_unresolved
          local ok, message = pcall(handlers.events[defines.events.on_research_started],
            {research = unresolved})
          assert(not ok and tostring(message):find("unsupported native research queue state", 1, true))
          assert(f_unresolved.cancelled == 0 and f_unresolved.current_research == unresolved
            and f_unresolved.research_progress == .75 and #f_unresolved.research_queue == 1
            and f_unresolved.research_queue[1] == unresolved_other,
            "unresolved current research was speculatively cancelled or rewritten")
        ''')

    def test_reversal_and_effect_reset_restore_only_mir_owned_cap_disablement(self):
        self.lua.execute('''
          local gear_name = "recipe-prod-research_gears-1"
          local worker_name = "worker-robots-speed-6"
          local gear = technology(gear_name, 3, true)
          local foreign = technology(gear_name, 3, false)
          local worker = technology(worker_name, 3, true)
          worker.prototype = {
            max_level = 4294967295,
            effects = {{type = "worker-robot-speed", modifier = .65}}
          }
          worker.prerequisites = {["worker-robots-speed-5"] = {name = "worker-robots-speed-5"}}
          local gear_force = force(30, {[gear_name] = gear}, {}, nil, nil)
          local worker_force = force(31, {[worker_name] = worker}, {}, nil, nil)
          local foreign_force = force(32, {[gear_name] = foreign}, {}, nil, nil)
          gear.force, worker.force, foreign.force = gear_force, worker_force, foreign_force
          boot({[30] = gear_force, [31] = worker_force, [32] = foreign_force}, 2, "", nil, nil, 2)
          assert(type(handlers.events[defines.events.on_research_reversed]) == "function")
          assert(type(handlers.events[defines.events.on_technology_effects_reset]) == "function")
          handlers.init()
          assert(not gear.enabled and gear.visible_when_disabled)
          assert(not worker.enabled and worker.visible_when_disabled)
          assert(not foreign.enabled and foreign.visible_when_disabled)
          assert(storage.mir_caps.owned_disabled[32][gear_name].disabled == nil,
            "foreign disablement was claimed by MIR")

          gear.level = 2
          handlers.events[defines.events.on_research_reversed]({research = gear})
          assert(gear.enabled and not gear.visible_when_disabled,
            "research reversal did not restore MIR-owned gear disablement below its cap")

          foreign.level = 2
          handlers.events[defines.events.on_research_reversed]({research = foreign})
          assert(not foreign.enabled,
            "research reversal re-enabled a foreign-disabled gear technology")

          worker.level = 2
          handlers.events[defines.events.on_technology_effects_reset]({force = worker_force})
          assert(worker.enabled and not worker.visible_when_disabled,
            "effects reset did not restore MIR-owned worker disablement below its cap")
        ''')

    def test_foreign_disable_and_force_lifecycle_cleanup_remain_owned(self):
        self.lua.execute('''
          local name = "recipe-prod-research_gears-1"
          local foreign = technology(name, 11, false)
          local source = force(7, {[name] = foreign}, {}, nil, nil)
          local destination = force(8, {[name] = technology(name, 10, true)}, {}, nil, nil)
          boot({[7] = source, [8] = destination}, 10)
          handlers.init()
          assert(not foreign.enabled and foreign.visible_when_disabled, "cap did not preserve foreign disablement")
          assert(storage.mir_caps.owned_disabled[7][name].disabled == nil,
            "unexpected foreign disable ownership: " .. tostring(storage.mir_caps.owned_disabled[7][name].disabled))
          local saved_storage = storage
          boot({[7] = source, [8] = destination}, 0, "", saved_storage)
          handlers.configuration()
          assert(not foreign.enabled and not foreign.visible_when_disabled, "uncap changed foreign enablement or visibility")
          saved_storage = storage
          boot({[7] = source, [8] = destination}, 10, "", saved_storage)
          handlers.configuration()
          storage.mir_caps.owned_disabled[8] = {stale = {disabled = true}}
          handlers.events[defines.events.on_force_created]({force = destination})
          assert(storage.mir_caps.owned_disabled[8] == nil, "force creation retained stale ownership")
          storage.mir_caps.owned_disabled[8] = {stale = {disabled = true}}
          handlers.events[defines.events.on_force_reset]({force = destination})
          assert(storage.mir_caps.owned_disabled[8] == nil, "force reset retained stale ownership")
          storage.mir_caps.owned_disabled[7].stale = {disabled = true}
          source.valid = false
          handlers.events[defines.events.on_forces_merged]({source_index = 7, destination = destination})
          assert(storage.mir_caps == nil, "merged source retained ownership")
          saved_storage = storage
          boot({[7] = source, [8] = destination}, 0, "", saved_storage)
          handlers.configuration()
          assert(storage.mir_caps == nil, "uncap retained empty ownership state")
        ''')

    def test_admitted_native_worker_tail_cap_is_per_force_and_restores_owned_state(self):
        self.lua.execute('''
          local owner = "worker-robots-speed-6"
          local predecessor = "worker-robots-speed-5"
          local function native_tail(level, enabled, effects)
            local value = technology(owner, level, enabled)
            value.prototype = {
              max_level = 4294967295,
              effects = effects or {{type = "worker-robot-speed", modifier = .65}}
            }
            value.prerequisites = {[predecessor] = {name = predecessor}}
            return value
          end
          local admitted = native_tail(11, true)
          local gear = technology("recipe-prod-research_gears-1", 1, true)
          local f = force(12, {[owner] = admitted, [gear.name] = gear}, {}, nil, nil)
          admitted.force = f
          boot({[12] = f}, 0, "", nil, nil, 10)
          local lifecycle = require("runtime.lifecycle")
          assert(lifecycle.caps_active())
          local limits = lifecycle.cap_limits(f)
          assert(limits[owner] == 10 and limits["recipe-prod-research_gears-1"] == 0)
          limits[owner] = 99
          assert(lifecycle.cap_limits(f)[owner] == 10, "cap snapshot was shared")
          handlers.init()
          assert(not admitted.enabled and admitted.visible_when_disabled and admitted.level == 11)
          assert(storage.mir_caps.owned_disabled[12][owner].disabled)

          local saved_storage = storage
          boot({[12] = f}, 0, "", saved_storage, nil, 0)
          handlers.configuration()
          assert(admitted.enabled and not admitted.visible_when_disabled and storage.mir_caps == nil,
            "unlimited native cap did not restore MIR-owned state")
          assert(require("runtime.lifecycle").cap_limits(f)[owner] == 0,
            "Library snapshot did not expose the unlimited native cap")

          local foreign = native_tail(11, false)
          local foreign_force = force(13, {[owner] = foreign}, {}, nil, nil)
          foreign.force = foreign_force
          boot({[13] = foreign_force}, 0, "", nil, nil, 10)
          handlers.init()
          assert(not foreign.enabled and foreign.visible_when_disabled)
          assert(storage.mir_caps.owned_disabled[13][owner].disabled == nil)
          saved_storage = storage
          boot({[13] = foreign_force}, 0, "", saved_storage, nil, 0)
          handlers.configuration()
          assert(not foreign.enabled and not foreign.visible_when_disabled,
            "native relaxation changed foreign enablement")

          local malformed = native_tail(11, true, {
            {type = "worker-robot-speed", modifier = .65},
            {type = "laboratory-speed", modifier = .1}
          })
          local malformed_force = force(14, {[owner] = malformed}, {}, nil, nil)
          malformed.force = malformed_force
          boot({[14] = malformed_force}, 0, "", nil, nil, 10)
          local malformed_limits = require("runtime.lifecycle").cap_limits(malformed_force)
          assert(malformed_limits[owner] == nil)
          handlers.init()
          assert(malformed.enabled and not malformed.visible_when_disabled and storage.mir_caps == nil,
            "malformed native tail was managed")
        ''')

    def test_k2_worker_variant_is_lazy_owned_and_does_not_inherit_another_effects_rights(self):
        self.lua.execute('''
          local name = "worker-robots-speed-7"
          local k2 = {Krastorio2 = "2.1.4", ['Krastorio2-spaced-out'] = "2.0.19",
            Krastorio2Assets = "2.1.0", ['k2so-assets'] = "1.0.7", ['space-age'] = "2.1.23"}
          local native = technology(name, 9, true)
          native.prototype = {max_level = 4294967295,
            effects = {{type = "worker-robot-speed", modifier = .6}}}
          native.prerequisites = {['worker-robots-speed-6'] = {name = "worker-robots-speed-6"}}
          local f = force(20, {[name] = native}, {}, nil, nil)
          native.force = f
          package.preload['compatibility.k2so_worker_speed'] = function() error("inactive adapter loaded") end
          boot({[20] = f}, 0, "", nil, nil, 8)
          assert(require('runtime.lifecycle').cap_limits(f)[name] == nil)
          assert(package.loaded['compatibility.k2so_worker_speed'] == nil)
          package.preload['compatibility.k2so_worker_speed'] = nil

          boot({[20] = f}, 0, "", nil, nil, 8, k2)
          assert(require('runtime.lifecycle').cap_limits(f)[name] == 8)
          handlers.init()
          assert(not native.enabled and native.visible_when_disabled)
          assert(storage.mir_caps.owned_disabled[20][name].worker_effect_modifier == .6)
          local saved = storage
          boot({[20] = f}, 0, "", saved, nil, 0, k2)
          handlers.configuration()
          assert(native.enabled and not native.visible_when_disabled and storage.mir_caps == nil)

          -- An untagged earlier private row only ever represented 0.65.
          native.enabled, native.visible_when_disabled = false, true
          saved = {mir_caps = {schema = 1, owned_disabled = {[20] = {[name] = {
            disabled = true, visible_when_disabled = false}}}}}
          boot({[20] = f}, 0, "", saved, nil, 0, k2)
          handlers.configuration()
          assert(not native.enabled and native.visible_when_disabled and storage.mir_caps == nil)

          -- A known 0.6 right cannot survive replacement by the 0.65 owner.
          saved = {mir_caps = {schema = 1, owned_disabled = {[20] = {[name] = {
            disabled = true, visible_when_disabled = false, worker_effect_modifier = .6}}}}}
          native.prototype.effects[1].modifier = .65
          boot({[20] = f}, 0, "", saved, nil, 0)
          handlers.configuration()
          assert(not native.enabled and native.visible_when_disabled and native.level == 9)
          assert(native.prototype.effects[1].modifier == .65 and storage.mir_caps == nil)
        ''')

    def test_worker_tail_binding_change_discards_stale_enablement_right(self):
        self.lua.execute('''
          local six = "worker-robots-speed-6"
          local seven = "worker-robots-speed-7"
          local function tail(name, predecessor, level, enabled, effects)
            local value = technology(name, level, enabled)
            value.prototype = {
              max_level = 4294967295,
              effects = effects or {{type = "worker-robot-speed", modifier = .65}}
            }
            value.prerequisites = {[predecessor] = {name = predecessor}}
            return value
          end
          local old_six = tail(six, "worker-robots-speed-5", 11, true)
          local f = force(15, {[six] = old_six}, {}, nil, nil)
          old_six.force = f
          boot({[15] = f}, 0, "", nil, nil, 10)
          handlers.init()
          assert(not old_six.enabled and storage.mir_caps.owned_disabled[15][six].disabled)

          old_six.prototype.effects = {
            {type = "worker-robot-speed", modifier = .65},
            {type = "laboratory-speed", modifier = .1}
          }
          local raw_technologies, tail_reads = f.technologies, 0
          f.technologies = setmetatable({}, {__index = function(_, name)
            if name == six or name == seven then tail_reads = tail_reads + 1 end
            return raw_technologies[name]
          end})
          handlers.configuration()
          assert(tail_reads == 2, "malformed tail selection examined more than two candidates")
          assert(storage.mir_caps == nil and not old_six.enabled and old_six.visible_when_disabled,
            "malformed upstream tail retained an enablement right or was re-enabled")

          local new_seven = tail(seven, six, 1, true)
          f.technologies[seven] = new_seven
          handlers.configuration()
          local limits = require("runtime.lifecycle").cap_limits(f)
          assert(limits[six] == nil and limits[seven] == 10,
            "higher-priority admitted tail did not replace the malformed binding")

          local saved_storage = storage
          boot({[15] = f}, 0, "", saved_storage, nil, 0)
          handlers.configuration()
          local foreign_replacement = tail(six, "worker-robots-speed-5", 11, false)
          f.technologies[six] = foreign_replacement
          handlers.configuration()
          assert(not foreign_replacement.enabled and not foreign_replacement.visible_when_disabled
              and storage.mir_caps == nil,
            "stale worker-six cap ownership re-enabled a foreign replacement")
        ''')

    def test_lifecycle_source_has_no_tick_or_runtime_generator_import(self):
        source = (ROOT / "source/runtime/lifecycle.lua").read_text()
        control = (ROOT / "source/control.lua").read_text(encoding="utf-8")
        bootstrap = (ROOT / "source/runtime/bootstrap.lua").read_text(encoding="utf-8")
        self.assertNotIn("on_tick", source)
        self.assertNotIn("generator", source.lower())
        self.assertNotIn("recycling_scope", source)
        self.assertNotIn("productivity_cap_scope", source)
        self.assertNotIn("game.recipe_prototypes", source)
        self.assertNotIn("cancel_current_research", source)
        self.assertNotIn("documented exception", source)
        self.assertNotIn("require(", source[source.index("function M.on_init"):])
        self.assertIn('require("runtime.bootstrap")', control)
        self.assertIn("function M.register()", bootstrap)
        self.assertIn("remote.add_interface", bootstrap)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LifecycleTests))
    sys.exit(0 if result.wasSuccessful() else 1)

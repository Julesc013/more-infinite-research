"""Finite native-continuation ownership controls; not native qualification."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]

# Independent names of the six optional extensions of shared Base research.
# Productivity research and private paid-state holders are outside this policy.
NATIVE_TAILS = (
    "braking-force-8", "inserter-capacity-bonus-8", "laser-shooting-speed-8",
    "research-speed-7", "weapon-shooting-speed-7", "worker-robots-storage-4",
)


class ContinuationOwnershipTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.globals().tail_names = self.lua.table_from(NATIVE_TAILS)
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          modern = require("compatibility.modern_catalogue")
          function ids(rows)
            local result = {}
            for _, row in ipairs(rows) do
              assert(not result[row.id], "duplicate authored continuation")
              result[row.id] = true
            end
            return result
          end
          function foreign_tail(name)
            local facts = {
              ["braking-force-8"]={"braking-force-7", {{type="train-braking-force-bonus", modifier=.27}}},
              ["inserter-capacity-bonus-8"]={"inserter-capacity-bonus-7", {
                {type="inserter-stack-size-bonus", modifier=1}, {type="bulk-inserter-capacity-bonus", modifier=2}}},
              ["laser-shooting-speed-8"]={"laser-shooting-speed-7", {{type="gun-speed", ammo_category="laser", modifier=.27}}},
              ["research-speed-7"]={"research-speed-6", {{type="laboratory-speed", modifier=.27}}},
              ["weapon-shooting-speed-7"]={"weapon-shooting-speed-6", {
                {type="gun-speed", ammo_category="bullet", modifier=.27}, {type="gun-speed", ammo_category="shotgun-shell", modifier=.27}}},
              ["worker-robots-storage-4"]={"worker-robots-storage-3", {{type="worker-robot-storage", modifier=1}}},
            }
            local fact = assert(facts[name])
            return {type="technology", name=name, max_level="infinite",
              prerequisites={fact[1], "foreign-prerequisite"}, effects=fact[2],
              unit={count_formula="123*2^(L-1)", time=37,
                ingredients={{"foreign-science-pack", 2}}}, marker="foreign"}
          end
          function runtime(technologies, creator)
            script = {active_mods={base="2.1.23", ["more-infinite-research"]="5.0.21002"}}
            local calls = {}
            prototypes = {technology=technologies, get_history=function(kind, name)
              assert(kind == "technology" and technologies[name] ~= nil)
              calls[name] = (calls[name] or 0) + 1
              return {created=creator, changed={"science-spread", "another-mod"}}
            end}
            game = setmetatable({}, {__index=function() error("read game during control parsing") end})
            package.loaded["research.catalogue"], package.loaded["runtime.catalogue"] = nil, nil
            return require("runtime.catalogue"), calls
          end
        ''')

    def test_uncolliding_six_native_extensions_remain_declared(self):
        self.lua.execute('''
          local selected, count = ids(modern.continuations({})), 0
          for _ in pairs(selected) do count = count + 1 end
          assert(count == 6)
          for _, name in ipairs(tail_names) do assert(selected[name], name) end
        ''')

    def test_each_existing_foreign_infinite_owner_is_preserved(self):
        self.lua.execute('''
          for _, name in ipairs(tail_names) do
            local foreign = foreign_tail(name)
            local effects, unit, prerequisites = foreign.effects, foreign.unit, foreign.prerequisites
            local modifier = effects[1].modifier
            local rows, owners = modern.continuations({}, {technology={[name]=foreign}})
            local selected = ids(rows)
            assert(not selected[name], "MIR retained foreign infinite tail " .. name)
            assert(owners[name] == foreign, "lost the admitted external owner for bounded coverage")
            for _, other in ipairs(tail_names) do
              if other ~= name then assert(selected[other], "lost unrelated tail " .. other) end
            end
            assert(foreign.effects == effects and foreign.effects[1].modifier == modifier)
            assert(foreign.unit == unit and unit.time == 37 and unit.count_formula == "123*2^(L-1)")
            assert(unit.ingredients[1][1] == "foreign-science-pack" and unit.ingredients[1][2] == 2)
            assert(foreign.prerequisites == prerequisites and prerequisites[2] == "foreign-prerequisite")
            assert(foreign.marker == "foreign" and foreign.max_level == "infinite")
          end
        ''')

    def test_multiple_external_native_tails_do_not_hide_unrelated_conflicts(self):
        self.lua.execute('''
          local technologies = {}
          for _, name in ipairs(tail_names) do technologies[name] = foreign_tail(name) end
          assert(next(ids(modern.continuations({}, {technology=technologies}))) == nil)
          local generator = require("research.generator")
          for _, name in ipairs({"recipe-prod-research_gears-1", "mir-legacy-module-credit-speed-module"}) do
            local writes = 0
            local ok, message = pcall(generator.install, {{type="technology", name=name}}, {
              raw={technology={[name]={marker="foreign"}}},
              extend=function() writes = writes + 1 end})
            assert(not ok and tostring(message):find("duplicate technology " .. name, 1, true))
            assert(writes == 0, "foreign conflict wrote prototypes")
          end
        ''')

    def test_internal_native_tail_duplicate_still_fails_before_any_write(self):
        self.lua.execute('''
          local generator, writes = require("research.generator"), 0
          local name = "weapon-shooting-speed-7"
          local ok, message = pcall(generator.install,
            {{type="technology", name=name}, {type="technology", name=name}}, {
              raw={technology={}}, extend=function() writes = writes + 1 end})
          assert(not ok and tostring(message):find("duplicate technology " .. name, 1, true))
          assert(writes == 0, "internal duplicate wrote prototypes")
        ''')

    def test_finite_or_unrelated_colliders_are_not_accepted_as_infinite_owners(self):
        self.lua.execute('''
          for _, name in ipairs(tail_names) do
            for _, mode in ipairs({"finite", "unrelated-effect", "wrong-anchor", "missing-unit"}) do
              local foreign = foreign_tail(name)
              if mode == "finite" then foreign.max_level = nil
              elseif mode == "unrelated-effect" then foreign.effects = {{type="laboratory-productivity", modifier=.1}}
              elseif mode == "wrong-anchor" then foreign.prerequisites = {"foreign-prerequisite"}
              else foreign.unit = nil end
              assert(ids(modern.continuations({}, {technology={[name]=foreign}}))[name],
                "invalid owner silently removed MIR's infinite family: " .. name .. ":" .. mode)
            end
          end
        ''')

    def test_muria_exact_finite_chain_selects_nine_and_preserves_default_effects(self):
        self.lua.execute('''
          local categories = {"bullet", "shotgun-shell", "cannon-shell", "rocket", "explosive-shotgun-shell"}
          local modifiers = {.25, .20, 1.35, .65, .20}
          local function stage(name, predecessor, count)
            local effects = {}
            for i, category in ipairs(categories) do effects[i] = {type="gun-speed", ammo_category=category, modifier=modifiers[i]} end
            return {type="technology", name=name, effects=effects, prerequisites={predecessor, "acidworking-science-pack"},
              unit={count=count, time=60, ingredients={{"automation-science-pack",1},{"logistic-science-pack",1},
                {"chemical-science-pack",1},{"military-science-pack",1},{"utility-science-pack",1},
                {"space-science-pack",1},{"acidworking-science-pack",1}}}}
          end
          local seven = stage("weapon-shooting-speed-7", "weapon-shooting-speed-6", 2500)
          local eight = stage("weapon-shooting-speed-8", "weapon-shooting-speed-7", 5000)
          local raw = {technology={[seven.name]=seven, [eight.name]=eight}}
          local rows = modern.continuations({Muria="1.8.5"}, raw)
          local definition
          for _, row in ipairs(rows) do
            assert(row.id ~= seven.name and row.id ~= eight.name)
            if row.id == "weapon-shooting-speed-9" then assert(not definition); definition = row end
          end
          assert(definition and definition.family == "weapon-shooting-speed" and definition.level == 9)
          assert(definition.predecessor == eight.name and #definition.prerequisites == 1)
          local config, startup = require("research.settings"), {}
          for _, spec in ipairs(config.prototypes()) do startup[spec.name] = {value=spec.default_value} end
          startup["mir-cost-base-weapon-shooting-speed"].value = 0
          startup["mir-cost-growth-weapon-shooting-speed"].value = 0
          startup["mir-research-time-weapon-shooting-speed"].value = 0
          local build = require("research.modern").continuation
          local output = build(definition, config.resolve(startup))
          assert(output.name == "weapon-shooting-speed-9" and output.max_level == "infinite")
          assert(output.prerequisites[1] == eight.name and #output.unit.ingredients == 7)
          assert(output.unit.ingredients[7][1] == "acidworking-science-pack" and output.unit.time == 60)
          assert(load("return function(L) return " .. output.unit.count_formula .. " end")()(9) == 10000)
          for index, effect in ipairs(output.effects) do
            assert(effect.type == "gun-speed" and effect.ammo_category == categories[index])
            assert(math.abs(effect.modifier - modifiers[index]) < 1e-12)
          end
          startup["mir-effect-per-level-weapon-shooting-speed"].value = 20
          local adjusted = build(definition, config.resolve(startup))
          for index, effect in ipairs(adjusted.effects) do assert(math.abs(effect.modifier - modifiers[index]/2) < 1e-12) end
          assert(seven.unit.count == 2500 and eight.unit.count == 5000 and eight.effects[3].modifier == 1.35)
          output.unit.ingredients[7][1] = "caller-mutated"
          assert(eight.unit.ingredients[7][1] == "acidworking-science-pack" and definition.ingredients[7][1] == "acidworking-science-pack")
          local generator, writes = require("research.generator"), 0
          local ok, message = pcall(generator.install, {adjusted}, {
            raw={technology={[adjusted.name]={}}}, extend=function() writes = writes + 1 end})
          assert(not ok and tostring(message):find("duplicate technology weapon-shooting-speed-9", 1, true) and writes == 0)
        ''')

    def test_foreign_creator_remains_external_after_later_modifications(self):
        self.lua.execute('''
          local technologies = setmetatable({}, {__pairs=function() error("world scan") end})
          for _, name in ipairs(tail_names) do technologies[name] = foreign_tail(name) end
          local catalogue, calls = runtime(technologies, "foreign-provider")
          for _ = 1, 2 do
            local declared = ids(catalogue.declared())
            for _, name in ipairs(tail_names) do assert(not declared[name], "claimed foreign tail " .. name) end
          end
          for _, name in ipairs(tail_names) do assert(calls[name] == 1, "creator lookup work " .. name) end
        ''')

    def test_mir_creator_retains_ownership_after_science_spread_modifications(self):
        self.lua.execute('''
          local technologies = {}
          for _, name in ipairs(tail_names) do technologies[name] = foreign_tail(name) end
          local catalogue, calls = runtime(technologies, "more-infinite-research")
          for _ = 1, 2 do
            local declared = ids(catalogue.declared())
            for _, name in ipairs(tail_names) do assert(declared[name], "lost MIR-created tail " .. name) end
          end
          for _, name in ipairs(tail_names) do assert(calls[name] == 1, "creator lookup work " .. name) end
        ''')

    def test_unqualified_muria_provider_changes_refuse_before_mir_state_writes(self):
        import test_lifecycle as fixture
        fixture.LuaRuntime = LuaRuntime
        harness = fixture.LifecycleTests()
        harness.setUp()
        harness.lua.execute('''
          local world=force(1,{}, {},nil,nil)
          for _, change in ipairs({{new_version="1.8.5"},{old_version="1.8.5"}}) do
            local saved=setmetatable({}, {__newindex=function() error("MIR wrote state before provider guard") end})
            boot({[1]=world},0,"",saved,nil,0,{base="2.1.23"})
            local ok,message=pcall(handlers.configuration,{mod_changes={Muria=change}})
            assert(not ok and tostring(message):find("cannot safely add or remove Muria",1,true),tostring(message))
            assert(next(saved)==nil and #world.research_queue==0)
          end
          -- Installing MIR for the first time beside an existing Muria world
          -- does not replace a previous MIR-owned weapon identity.
          boot({[1]=world},0,"",nil,nil,0,{base="2.1.23"})
          handlers.configuration({mod_changes={Muria={new_version="1.8.5"},
            ["more-infinite-research"]={new_version="5.0.21002"}}})
        ''')

    def test_all_six_foreign_creators_stay_out_of_real_cap_admission(self):
        self.lua.execute('''
          local settings_names={
            ["braking-force-8"]="mir-max-level-braking-force",
            ["inserter-capacity-bonus-8"]="mir-max-level-inserter-capacity-bonus",
            ["laser-shooting-speed-8"]="mir-max-level-laser-shooting-speed",
            ["research-speed-7"]="mir-max-level-research-speed",
            ["weapon-shooting-speed-7"]="mir-max-level-weapon-shooting-speed",
            ["worker-robots-storage-4"]="mir-max-level-worker-robots-storage",
          }
          local config=require("research.settings")
          for _,name in ipairs(tail_names) do
            for _,creator in ipairs({"more-infinite-research","foreign-provider"}) do
              for _,enabled in ipairs({false,true}) do
                script={active_mods={base="2.1.23"}}
                settings={startup={}}
                for _,spec in ipairs(config.prototypes()) do settings.startup[spec.name]={value=spec.default_value} end
                settings.startup[settings_names[name]].value=10
                local native={name=name,valid=true,level=11,enabled=enabled,researched=false,
                  visible_when_disabled=false,saved_progress=.27,prototype={enabled=true}}
                local current={name="foreign-current",valid=true}
                local world={index=1,valid=true,technologies={[name]=native,[current.name]=current},
                  research_queue={current,native},current_research=current,research_progress=.42}
                current.force,native.force=world,world
                local reads=0
                prototypes={recipe={},technology=setmetatable({[name]=native.prototype},
                  {__pairs=function() error("cap admission enumerated all prototypes") end}),
                  get_history=function(kind,id)
                    assert(kind=="technology" and id==name);reads=reads+1
                    return {created=creator,changed={"science-spread","more-infinite-research"}}
                  end}
                game={forces={[1]=world}}
                storage={mir_caps={schema=1,owned_disabled={[1]={[name]={disabled=true,visible_when_disabled=false}}}}}
                for _,module in ipairs({"research.catalogue","runtime.catalogue","runtime.lifecycle","runtime.configuration"}) do
                  package.loaded[module]=nil
                end
                local lifecycle=require("runtime.lifecycle")
                local owned=creator=="more-infinite-research"
                local limits=lifecycle.cap_limits(world)
                assert((limits[name]~=nil)==owned,"incorrect cap ownership for "..name)
                lifecycle.on_init()
                assert(native.enabled==(not owned and enabled) and native.visible_when_disabled==owned)
                assert(native.level==11 and native.saved_progress==.27 and not native.researched)
                assert(#world.research_queue==(owned and 1 or 2) and world.research_queue[1]==current)
                assert(world.current_research==current and world.research_progress==.42 and reads==1)
                local records=storage.mir_caps and storage.mir_caps.owned_disabled[1]
                if not owned then assert(records==nil or records[name]==nil,"stale restoration right survived") end
              end
            end
          end
        ''')

    def test_unknown_creation_history_refuses_each_shared_identity(self):
        self.lua.execute('''
          for _,name in ipairs(tail_names) do
            script={active_mods={base="2.1.23"}}
            prototypes={technology={[name]={}},get_history=function() return {changed={"science-spread"}} end}
            package.loaded["research.catalogue"],package.loaded["runtime.catalogue"]=nil,nil
            local ok,message=pcall(require,"runtime.catalogue")
            assert(not ok and tostring(message):find("creation history for "..name,1,true))
          end
        ''')

    def test_exclusive_muria_tail_custody_is_checked_before_cap_admission(self):
        self.lua.execute('''
          for _,creator in ipairs({"more-infinite-research","foreign-provider"}) do
            local name="weapon-shooting-speed-9"
            local prototype={name=name,enabled=true}
            local native={name=name,valid=true,level=11,enabled=true,researched=false,
              visible_when_disabled=false,saved_progress=.27,prototype=prototype}
            local world={index=1,valid=true,technologies={[name]=native},research_queue={}}
            local reads=0
            script={active_mods={base="2.1.23",Muria="1.8.5"}}
            prototypes={recipe={},technology={[name]=prototype},get_history=function(kind,id)
              assert(kind=="technology" and id==name);reads=reads+1
              return {created=creator,changed={"science-spread"}}
            end}
            game=setmetatable({}, {__index=function() error("custody check read game") end})
            storage=setmetatable({}, {__newindex=function() error("custody check wrote state") end})
            for _,module in ipairs({"research.catalogue","runtime.catalogue","runtime.lifecycle","runtime.configuration"}) do
              package.loaded[module]=nil
            end
            local ok,catalogue=pcall(require,"runtime.catalogue")
            assert(reads==1 and native.enabled and native.saved_progress==.27 and next(storage)==nil)
            if creator=="foreign-provider" then
              assert(not ok and tostring(catalogue):find("MIR creation custody for "..name,1,true),tostring(catalogue))
            else
              assert(ok and ids(catalogue.declared())[name] and not catalogue.externally_supplied_continuation(name))
              local config=require("research.settings")
              settings={startup={}}
              for _,spec in ipairs(config.prototypes()) do settings.startup[spec.name]={value=spec.default_value} end
              settings.startup["mir-max-level-weapon-shooting-speed"].value=10
              local lifecycle=require("runtime.lifecycle")
              game,storage={forces={[1]=world}},{}
              assert(lifecycle.cap_limits(world)[name]==10)
              lifecycle.on_init()
              assert(not native.enabled and native.level==11 and native.saved_progress==.27)
              assert(storage.mir_caps.owned_disabled[1][name])
            end
          end
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(ContinuationOwnershipTests))
    sys.exit(0 if result.wasSuccessful() else 1)

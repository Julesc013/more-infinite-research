import json
import pathlib
import sys

runtime_dir, staged_control_path, data_updates_path, data_final_path, old_updates_path, runtime_control_path = sys.argv[1:]
sys.path.insert(0, runtime_dir)
from lupa import lua52

assertions = 0

def check(condition, message):
    global assertions
    if not condition:
        raise AssertionError(message)
    assertions += 1

def lua():
    return lua52.LuaRuntime(unpack_returned_tuples=True)

def base_input(version):
    return f'''
mods = {{["more-infinite-research"] = "{version}", ["space-age"] = "2.1.23"}}
logs = {{}}
log = function(value) logs[#logs + 1] = value end
data = {{raw = {{}}}}
data.raw.item = {{}}
data.raw.recipe = {{
  ["space-science-pack"] = {{enabled = true, result = "space-science-pack", result_count = 1}}
}}
data.raw.technology = {{
  ["space-science-pack"] = {{unit = {{count = 100, ingredients = {{{{"automation-science-pack", 1}}}}}}, research_trigger = {{type = "build-entity", entity = "asteroid-collector"}}, prerequisites = {{"space-platform"}}, effects = {{{{type = "unlock-recipe", recipe = "space-science-pack"}}}}}}
}}
function data:extend(rows)
  for _, row in pairs(rows) do
    self.raw[row.type] = self.raw[row.type] or {{}}
    self.raw[row.type][row.name] = row
  end
end
'''
def execute_data(path, version):
    runtime = lua()
    runtime.execute(base_input(version))
    runtime.execute(pathlib.Path(path).read_text(encoding="utf-8"))
    return runtime

def check_target_shape(runtime, label):
    check(runtime.eval('data.raw.item.satellite ~= nil'), label + ': satellite absent')
    check(runtime.eval('data.raw.item.satellite.rocket_launch_products[1].type == "item" and data.raw.item.satellite.rocket_launch_products[1].name == "space-science-pack" and data.raw.item.satellite.rocket_launch_products[1].amount == 1000'), label + ': satellite product differs')
    check(runtime.eval('data.raw.recipe["space-science-pack"].enabled == false and data.raw.recipe["space-science-pack"].results[1].type == "item" and data.raw.recipe["space-science-pack"].results[1].name == "space-science-pack"'), label + ': recipe shape differs')
    check(runtime.eval('data.raw.technology["space-science-pack"].research_trigger.type == "send-item-to-orbit" and data.raw.technology["space-science-pack"].research_trigger.item == "satellite" and data.raw.technology["space-science-pack"].prerequisites[1] == "rocket-silo" and next(data.raw.technology["space-science-pack"].effects) == nil'), label + ': technology shape differs')

full = pathlib.Path(staged_control_path).read_text(encoding="utf-8")
runtime = lua()
runtime.execute('settings={startup={["mir-upgrade-archetype"]={value="space-age-native-owner"}}};storage={};game={forces={player={technologies={}}}};script={on_init=function(_) end,on_configuration_changed=function(_) end,on_load=function(_) end,on_event=function(_,_) end};defines={events={on_tick=1}}')
loader = runtime.eval('function(text) local chunk, err = load(text); if not chunk then error(err) end return true end')
check(loader(full), 'full staged generic fixture did not Lua-load')
predicate = runtime.execute(full + '\nreturn trigger_output_representative_delta')
before = runtime.eval('{hidden=false, prerequisites={"space-platform"}, ingredients={{name="space-science-pack",amount=1}}, effects={{type="unlock-recipe",recipe="space-science-pack"}}, unit_count=100}')
after = runtime.eval('{hidden=false, prerequisites={"rocket-silo"}, ingredients={{name="space-science-pack",amount=1}}, effects={}, unit_count=100}')
check(predicate("space-science-pack", before, after), 'exact two-field trigger-output delta was refused')
science_changed = runtime.eval('{hidden=false, prerequisites={"rocket-silo"}, ingredients={{name="cryogenic-science-pack",amount=1}}, effects={}, unit_count=100}')
effects_changed = runtime.eval('{hidden=false, prerequisites={"rocket-silo"}, ingredients={{name="space-science-pack",amount=1}}, effects={{type="unlock-recipe",recipe="space-science-pack"}}, unit_count=100}')
state_changed = runtime.eval('{hidden=true, prerequisites={"rocket-silo"}, ingredients={{name="space-science-pack",amount=1}}, effects={}, unit_count=100}')
check(not predicate("space-science-pack", before, science_changed), 'science delta was silently allowed')
check(not predicate("space-science-pack", before, effects_changed), 'effect delta was silently allowed')
check(not predicate("other-technology", before, after), 'other technology delta was silently allowed')
check(not predicate("space-science-pack", before, state_changed), 'unrelated state delta was silently allowed')

source = execute_data(data_updates_path, "4.6.21000")
check(source.eval('data.raw.item.satellite == nil and data.raw.recipe["space-science-pack"].enabled == true and data.raw.technology["space-science-pack"].research_trigger.type == "build-entity"'), 'successful companion mutated published 4.6 source')
target = execute_data(data_updates_path, "4.7.21000")
check_target_shape(target, 'target companion')
check(target.eval('data.raw.technology["space-science-pack"].unit == nil'), 'target companion: technology unit was not cleared')
check(target.eval('data.raw.recipe["space-science-pack"].result == nil and data.raw.recipe["space-science-pack"].result_count == nil'), 'target companion: legacy recipe result fields were retained')
old = execute_data(old_updates_path, "4.6.21000")
check_target_shape(old, 'old-source override')
old_target = execute_data(old_updates_path, "4.7.21000")
check(old_target.eval('data.raw.item.satellite == nil and data.raw.recipe["space-science-pack"].enabled == true'), 'old-source override leaked into target version')

runtime = target
runtime.execute('''
data.raw.recipe["cryogenic-science-pack"] = {results={{type="item",name="cryogenic-science-pack",amount=1}}}
data.raw.technology["cryogenic-science-pack"] = {research_trigger={type="craft-item",item="cryogenic-plant"},prerequisites={"cryogenic-plant"},effects={{type="unlock-recipe",recipe="cryogenic-science-pack"}}}
data.raw.technology["space-path"] = {prerequisites={"space-science-pack"}}
data.raw.technology["recipe-prod-research_ice-1"] = {unit={ingredients={{name="space-science-pack",amount=1},{name="cryogenic-science-pack",amount=1}}},prerequisites={"space-path"},effects={}}
data.raw.technology["asteroid-productivity"] = {effects={{type="change-recipe-productivity",recipe="oxide-asteroid-crushing",change=0.10},{type="change-recipe-productivity",recipe="advanced-oxide-asteroid-crushing",change=0.10}}}
data.raw.technology["recipe-prod-research_platform-1"] = {unit={ingredients={{name="space-science-pack",amount=1},{name="cryogenic-science-pack",amount=1}}},prerequisites={"space-path"},effects={{type="change-recipe-productivity",recipe="ice-platform",change=0.10},{type="change-recipe-productivity",recipe="space-platform-foundation",change=0.05}}}
data.raw.lab = {lab={inputs={"automation-science-pack","space-science-pack","cryogenic-science-pack"}}}
data.raw["mod-data"] = {["more-infinite-research-generation-plan"]={data={schema=1,kind="mir-generation-plan-public",generation_plan_schema=3,plan_fingerprint="PLAN",public_fingerprint="PUBLIC",validation_summary={valid=true}}}}
''')
runtime.execute(pathlib.Path(data_final_path).read_text(encoding="utf-8"))
check(runtime.eval('logs[#logs] == "[mir-trigger-output-fixture] data-stage=target binding=declared-trigger-output cryogenic=declared-recipe"'), 'data-final target marker missing')
source_final = lua()
source_final.execute(base_input("4.6.21000"))
source_final.execute(pathlib.Path(data_final_path).read_text(encoding="utf-8"))
check(source_final.eval("#logs == 0"), 'data-final companion was not inert on published source')
# Execute the real companion through the complete source -> target -> load ->
# tick lifecycle.  The mock deliberately raises if the retired
# game.technology_prototypes API is consulted; modern 2.1 code must read
# prototypes.technology instead.
def runtime_fixture(include_space_science=True, correct_owner_effects=True, duplicate_ice_effect=False):
    science = '{name="space-science-pack", amount=1},{name="cryogenic-science-pack", amount=1}' if include_space_science else '{name="cryogenic-science-pack", amount=1}'
    owner_second = 'advanced-oxide-asteroid-crushing' if correct_owner_effects else 'incorrect-oxide-recipe'
    ice_effects = '{type="change-recipe-productivity",recipe="oxide-asteroid-crushing",change=0.20}' if duplicate_ice_effect else ''
    lua_source = r'''
logs = {}
log = function(value) logs[#logs + 1] = value end
callbacks = {}
script = {
  active_mods = {["more-infinite-research"] = "4.6.21000", ["space-age"] = "2.1.23"},
  on_init = function(fn) callbacks.init = fn end,
  on_configuration_changed = function(fn) callbacks.configuration_changed = fn end,
  on_load = function(fn) callbacks.load = fn end,
  on_event = function(_, fn) callbacks.tick = fn end
}
defines = {events = {on_tick = 1}}
storage = {}
local space = {prerequisites = {}}
local path = {prerequisites = {["space-science-pack"] = space}}
prototypes = {technology = {
  ["space-science-pack"] = space,
  ["space-path"] = path,
  ["recipe-prod-research_ice-1"] = {prerequisites = {["space-path"] = path}},
  ["recipe-prod-research_platform-1"] = {prerequisites = {["space-path"] = path}},
  ["asteroid-productivity"] = {prerequisites = {}}
}}
local sciences = {__SCIENCES__}
local ice_effects = {__ICE_EFFECTS__}
local owner_effects = {
  {type="change-recipe-productivity", recipe="oxide-asteroid-crushing", change=0.10},
  {type="change-recipe-productivity", recipe="__OWNER_SECOND__", change=0.10}
}
local platform_effects = {
  {type="change-recipe-productivity", recipe="ice-platform", change=0.10},
  {type="change-recipe-productivity", recipe="space-platform-foundation", change=0.05}
}
game = setmetatable({forces = {player = {technologies = {
  ["recipe-prod-research_ice-1"] = {research_unit_ingredients = sciences, prototype = {effects = ice_effects}},
  ["recipe-prod-research_platform-1"] = {research_unit_ingredients = sciences, prototype = {effects = platform_effects}},
  ["asteroid-productivity"] = {research_unit_ingredients = {}, prototype = {effects = owner_effects}}
}}}}, {
  __index = function(_, key)
    if key == "technology_prototypes" then error("retired game.technology_prototypes access") end
    return nil
  end
})
'''
    runtime = lua()
    runtime.execute(lua_source.replace('__SCIENCES__', science).replace('__OWNER_SECOND__', owner_second).replace('__ICE_EFFECTS__', ice_effects))
    return runtime

control_text = pathlib.Path(runtime_control_path).read_text(encoding="utf-8")
runtime = runtime_fixture()
runtime.execute(control_text)
runtime.execute('callbacks.init()')
check(runtime.eval('logs[1] == "[mir-trigger-output-fixture] stage=source untouched-published-input=1"'), 'runtime source marker missing')
runtime.execute('script.active_mods["more-infinite-research"] = "4.7.21000"; callbacks.configuration_changed({}); callbacks.load(); callbacks.tick({})')
check(runtime.eval('logs[2] == "[mir-trigger-output-fixture] stage=upgrade emitted-science-prerequisite-effects=verified" and logs[3] == "[mir-trigger-output-fixture] stage=reload emitted-science-prerequisite-effects=verified"'), 'runtime target lifecycle marker sequence differs')

for description, arguments, expected in (
    ('science', {'include_space_science': False}, 'generated science vector is incomplete'),
    ('owner-effect', {'correct_owner_effects': False}, 'existing asteroid productivity owner effect changed'),
    ('duplicate-ice-effect', {'duplicate_ice_effect': True}, 'generated ice productivity duplicates existing owner'),
):
    runtime = runtime_fixture(**arguments)
    runtime.execute(control_text)
    runtime.execute('callbacks.init(); script.active_mods["more-infinite-research"] = "4.7.21000"')
    rejected = False
    try:
        runtime.execute('callbacks.configuration_changed({})')
    except Exception as error:
        detail = str(error)
        check(expected in detail and 'retired game.technology_prototypes access' not in detail, description + ': wrong rejection boundary')
        rejected = True
    check(rejected, description + ': altered runtime input was accepted')
print(json.dumps({"status": "passed", "assertions": assertions}, sort_keys=True))

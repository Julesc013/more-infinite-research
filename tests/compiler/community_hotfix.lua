-- Controlled current-source regressions. No native engine or ecosystem claim.
local base_version = rawget(_G, "MIR_COMMUNITY_TEST_BASE_VERSION") or "2.1.20"
mods = {base = base_version}
settings = {startup = {}}
log = function() end
data = {raw = {recipe = {}, item = {}, technology = {}, lab = {}}}
function data:extend(rows)
  for _, row in ipairs(rows) do
    self.raw[row.type] = self.raw[row.type] or {}
    self.raw[row.type][row.name] = row
  end
end
local context = require("prototypes.mir.pipeline.compiler_context")
local assertions = 0
local function check(condition, detail)
  assert(condition, detail)
  assertions = assertions + 1
  print("OBSERVED\t" .. detail)
end
local function has(rows, name)
  for _, row in ipairs(rows or {}) do
    if (type(row) == "table" and (row.name or row[1]) or row) == name then return true end
  end
  return false
end
local function amount(rows, name)
  for _, row in ipairs(rows or {}) do
    if type(row) == "table" and (row.name or row[1]) == name then return row.amount or row[2] end
  end
end
local streams = require("prototypes.streams.productivity")
local registry = require("prototypes.mir.streams.registry")
streams = registry.view()
local catalog = require("prototypes.mir.settings.catalog")
local visibility = require("prototypes.mir.settings.visibility")
local builder = require("prototypes.mir.settings.builder")
local resolver = require("prototypes.mir.settings.resolver")
local effective = require("prototypes.mir.settings.effective")
local breed = streams.research_breeding
local specs = catalog.stream_setting_specs("research_breeding", breed)
check(#specs == 7, "Breeding retains all seven existing control identities")
for _, active in ipairs({{base="2.1.20"}, {base="2.1.20", ["space-age"]="2.1.20"}}) do
  local result = visibility.evaluate(breed, {mods=active})
  for _, spec in ipairs(specs) do
    local setting = builder.apply_visibility({name=spec.name}, result)
    check(setting.hidden ~= true, "Breeding control visible: " .. spec.name .. " Space Age=" .. tostring(active["space-age"] ~= nil))
  end
end
settings.startup["ips-enable-research_breeding"] = {value=false}
settings.startup["ips-research-time-research_breeding"] = {value=43}
context.with_active(context.new(), function()
  check(not resolver.stream_enabled("research_breeding", breed), "Existing disabled breeding value remains effective")
  check(effective.get("ips-research-time-research_breeding") == 43, "Existing breeding research time remains effective")
end)
-- Exercise real imported-value selection/catalog validation; profile transport
-- is a controlled fixture boundary, not a native compression round trip.
local codec = require("prototypes.mir.settings.profile_codec")
local original_decode = codec.decode
codec.decode = function() return {settings={
  ["ips-enable-research_breeding"]=false,
  ["ips-research-time-research_breeding"]=47
}} end
settings.startup[codec.import_setting_name] = {value="controlled-profile"}
context.with_active(context.new(), function()
  check(not resolver.stream_enabled("research_breeding", breed), "Imported breeding disable remains effective")
  check(effective.get("ips-research-time-research_breeding") == 47, "Imported breeding time remains effective")
end)
codec.decode = original_decode
settings.startup[codec.import_setting_name] = {value=""}

-- Use real facts/matching/effect construction against bounded recipe inputs.
-- Prototype identities were read from the existing upstream archive library.
local matcher = require("prototypes.mir.capabilities.recipe_productivity.recipe_matching")
local effects = require("prototypes.mir.capabilities.recipe_productivity.planner")
local requested = {
  {"industrial-furnace", "research_furnace", 0.02},
  {"se-space-solar-panel", "research_electric_energy", 0.05},
  {"se-space-solar-panel-2", "research_electric_energy", 0.02},
  {"se-space-solar-panel-3", "research_electric_energy", 0.01},
  {"se-space-accumulator", "research_electric_energy", 0.05},
  {"se-space-accumulator-2", "research_electric_energy", 0.02},
  {"solar-matrix", "research_electric_energy", 0.05},
  {"accumulator-v2", "research_electric_energy", 0.05}
}
local function recipe(name, output, category)
  data.raw.recipe[name] = {type="recipe", name=name, enabled=false,
    categories={category or "crafting"}, ingredients={{type="item",name="iron-plate",amount=2}},
    results={{type="item",name=output,amount=1}}}
  data.raw.item[output] = {type="item",name=output,stack_size=50}
end
recipe("solar-panel", "solar-panel")
recipe("accumulator", "accumulator")
for _, row in ipairs(requested) do recipe(row[1], row[1], row[1]:match("^se%-") and "space-manufacturing" or "crafting") end
recipe("solar-panel-recycling", "solar-panel", "recycling")
recipe("se-space-solar-panel-3-recycling", "se-space-solar-panel-3", "recycling")
recipe("hidden-solar-matrix", "solar-matrix")
data.raw.recipe["hidden-solar-matrix"].hidden = true
recipe("fish-breeding", "raw-fish")
recipe("iron-bacteria-cultivation", "iron-bacteria")
recipe("copper-bacteria-cultivation", "copper-bacteria")
context.with_active(context.new(), function()
  local assigned = {}
  for _, key in ipairs({"research_furnace", "research_electric_energy"}) do
    local rows = effects.effects_from_buckets(key, matcher.buckets_view(key, streams[key], 0.1))
    for _, effect in ipairs(rows) do
      check(effect.type == "change-recipe-productivity", "Manufacturing modifier: " .. effect.recipe)
      check(not assigned[effect.recipe], "Single manufacturing owner: " .. effect.recipe)
      assigned[effect.recipe] = {key=key, change=effect.change}
    end
  end
  for _, row in ipairs(requested) do
    local actual = assigned[row[1]]
    check(actual and actual.key == row[2] and actual.change == row[3], "Requested recipe/tier: " .. row[1])
  end
  check(assigned["solar-panel"].change == 0.1 and assigned.accumulator.change == 0.1, "Vanilla manufacturing bonuses retain their original tier")
  check(not assigned["solar-panel-recycling"] and not assigned["se-space-solar-panel-3-recycling"], "Recycling routes remain excluded")
  check(not assigned["hidden-solar-matrix"], "Hidden manufacturing route remains excluded")
  local breeds = matcher.buckets_view("research_breeding", breed, 0.1)
  local recipes = {}
  for _, bucket in ipairs(breeds) do for _, name in ipairs(bucket.recipes) do recipes[#recipes+1]=name end end
  check(has(recipes,"fish-breeding"), "Non-Space-Age eligible breeding recipe retains coverage")
  check(not has(recipes,"iron-bacteria-cultivation") and not has(recipes,"copper-bacteria-cultivation"), "Bacteria cultivation remains separate from breeding")
end)
-- Absence of the requested mods/recipes creates no dangling effect references.
for _, row in ipairs(requested) do data.raw.recipe[row[1]]=nil; data.raw.item[row[1]]=nil end
data.raw.recipe["hidden-solar-matrix"] = nil
context.with_active(context.new(), function()
  local rows = effects.effects_from_buckets("research_electric_energy", matcher.buckets_view("research_electric_energy", streams.research_electric_energy, 0.1))
  check(#rows == 2, "No added references when requested equipment is absent")
end)

-- The existing policy now excludes retained-but-retired space science.
local authority = require("prototypes.mir.compatibility.policy_authority")
local selector = require("prototypes.mir.capabilities.science_integration.science_selector")
local science_planner = require("prototypes.mir.planner.science")
local prerequisites = require("prototypes.mir.planner.prerequisites")
local science = require("prototypes.mir.capabilities.science_integration.science_packs")
local continuation_qualifier = require("prototypes.mir.planner.base_continuations.qualify")
local defaults = require("prototypes.mir.settings.defaults")
local packs = {"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","military-science-pack","utility-science-pack","space-science-pack"}
for _, pack in ipairs(packs) do
  data.raw.item[pack] = {type="item",name=pack,stack_size=200}
  data.raw.technology[pack] = {type="technology",name=pack,enabled=true,effects={},unit={count=1,ingredients={{"automation-science-pack",1}},time=1}}
  data.raw.recipe[pack] = {type="recipe",name=pack,enabled=true,ingredients={},results={{type="item",name=pack,amount=1}},categories={"crafting"}}
end
data.raw.lab.lab = {type="lab",name="lab",inputs=packs}
data.raw.item["lab-kit"] = {type="item",name="lab-kit",place_result="lab",stack_size=50}
data.raw.recipe["lab-kit"] = {type="recipe",name="lab-kit",enabled=true,category="crafting",ingredients={},results={{type="item",name="lab-kit",amount=1}}}
data.raw.character = {character={type="character",name="character",crafting_categories={"crafting"}}}
mods["space-is-fake"] = rawget(_G, "MIR_COMMUNITY_TEST_SIF_VERSION") or "1.0.76"
mods["space-age"] = base_version
-- A retained pack can still look craftable to generic supply/lab inference.
-- The explicit retirement role must win even in this opposing case.
data.raw.item["space-science-pack"].hidden = false
data.raw.recipe["space-science-pack"].hidden = false
data.raw.technology["space-science-pack"].enabled = false
data.raw.technology["space-science-pack"].hidden = true
settings.startup["ips-require-space-gate"] = {value=false}
settings.startup["mir-lab-incompatibility-policy"] = {value="reduce"}
local modes = {"configured","space","space-and-promethium","space-age-progression","official-progression","all-official","all"}
data.raw["ammo-category"] = {bullet={type="ammo-category",name="bullet"}}
for _, key in ipairs({"weapon-shooting-speed", "research-speed"}) do
  for level = 5, 6 do
    data.raw.technology[key .. "-" .. level] = {
      type="technology",name=key .. "-" .. level,enabled=true,
      icon="__base__/graphics/technology/research-speed.png",icon_size=256,
      effects={key == "research-speed" and {type="laboratory-speed",modifier=0.4} or {type="gun-speed",ammo_category="bullet",modifier=0.4}},
      prerequisites={},unit={count=1000*level,time=30,ingredients={{"automation-science-pack",2},{"utility-science-pack",3},{"space-science-pack",1}}}
    }
  end
end
local continuations = require("prototypes.mir.planner.base_continuations.plan")
for _, mode in ipairs(modes) do
  settings.startup["mir-science-pack-ingredient-policy"] = {value=mode}
  context.with_active(context.new(), function()
    check(science.science_pack_exists("space-science-pack"), "Retired pack still passes prototype/lab membership: " .. mode)
    local roles = authority.science_roles_for_stream("research_concrete")
    check(#roles > 0 and roles[#roles].role == "exclude", "Space Is Fake supplies a retirement role: " .. mode)
    for _, key in ipairs({"research_concrete","research_walls","research_rails","research_belts"}) do
      check(streams[key] ~= nil, "Actual affected stream declaration: " .. key)
      local selected = selector.pick_science_for_stream(streams[key], key)
      check(#selected > 0 and not has(selected,"space-science-pack"), "No retired pack after expansion: " .. key .. " " .. mode)
      local final, status = science_planner.ingredients_for_selected(key, selected)
      check(final and #final > 0 and not has(final,"space-science-pack"), "Nonempty final lab-compatible science: " .. key .. " " .. mode .. " " .. tostring(status))
      local reqs, reason = prerequisites.build_for(key, final)
      check(not reason and not has(reqs,"space-science-pack"), "No retired prerequisite: " .. key .. " " .. mode)
    end
    for _, key in ipairs({"weapon-shooting-speed", "research-speed"}) do
      local inherited = {ingredients={{"automation-science-pack",2},{name="utility-science-pack",amount=3},{"space-science-pack",1}}}
      local final, status = continuation_qualifier.resolve_ingredients(defaults.base_extensions[key], inherited, key)
      check(final and #final > 0 and not has(final,"space-science-pack"), "No retired continuation science: " .. key .. " " .. mode .. " " .. tostring(status))
      check(amount(final,"automation-science-pack") == 2 and amount(final,"utility-science-pack") == 3, "Continuation preserves inherited science amounts: " .. key .. " " .. mode)
      check(inherited.ingredients[1][2] == 2 and inherited.ingredients[2].amount == 3 and #inherited.ingredients == 3 and inherited.ingredients[3][1] == "space-science-pack", "Continuation science leaves upstream unit untouched: " .. key .. " " .. mode)
      local reqs, reason = continuation_qualifier.append_end_game_prerequisite({key .. "-6"}, final)
      check(not reason and has(reqs,key .. "-6") and not has(reqs,"space-science-pack"), "Continuation retains its finite anchor without retired prerequisite: " .. key .. " " .. mode)
    end
    local planned = {}
    for _, operation in ipairs(continuations.plan_all()) do planned[operation.technology_name] = operation end
    for _, key in ipairs({"weapon-shooting-speed", "research-speed"}) do
      local operation = planned[key .. "-7"]
      check(operation and operation.manifest_id == "base-continuation/" .. key, "Actual level-7 continuation remains planned with its stable identity: " .. key .. " " .. mode)
      check(#operation.technology.unit.ingredients > 0 and not has(operation.technology.unit.ingredients,"space-science-pack"), "Actual level-7 technology has no retired science: " .. key .. " " .. mode)
      check(amount(operation.technology.unit.ingredients,"automation-science-pack") == 2 and amount(operation.technology.unit.ingredients,"utility-science-pack") == 3, "Actual level-7 technology preserves inherited science amounts: " .. key .. " " .. mode)
      check(has(operation.technology.prerequisites,key .. "-6") and not has(operation.technology.prerequisites,"space-science-pack"), "Actual level-7 technology retains its finite anchor: " .. key .. " " .. mode)
      check(data.raw.technology[key .. "-7"] == nil, "Science planning leaves prototype emission to the existing emitter: " .. key .. " " .. mode)
    end
    require("prototypes.mir.pipeline.compiler_orchestrator.phase_invocation").apply_base_extensions(context.current())
    local generated = require("prototypes.mir.domain.facts.generated_technology_registry")
    for _, key in ipairs({"weapon-shooting-speed", "research-speed"}) do
      local actual = data.raw.technology[key .. "-7"]
      check(actual and #actual.unit.ingredients > 0 and not has(actual.unit.ingredients, "space-science-pack"), "Emitted level-7 technology has no retired science: " .. key .. " " .. mode)
      check(has(actual.prerequisites, key .. "-6") and not has(actual.prerequisites, "space-science-pack"), "Emitted level-7 technology retains its finite anchor: " .. key .. " " .. mode)
      local owner = generated.get(key .. "-7")
      check(owner and owner.kind == "base_extension" and owner.key == key, "Emitted level-7 technology retains native continuation ownership: " .. key .. " " .. mode)
    end
  end)
  for _, key in ipairs({"weapon-shooting-speed", "research-speed"}) do data.raw.technology[key .. "-7"] = nil end
end
-- Compatibility exclusions cannot retire the compiler's mandatory gates.
local policy_authority = require("prototypes.mir.compatibility.policy_authority")
local original_roles = policy_authority.science_roles_for_stream
policy_authority.science_roles_for_stream = function(key)
  local roles = original_roles(key)
  roles[#roles + 1] = {role="exclude",pack="cryogenic-science-pack"}
  return roles
end
settings.startup["mir-science-pack-ingredient-policy"] = {value="configured"}
context.with_active(context.new(), function()
  for _, key in ipairs({"research_ice", "research_platform"}) do
    local selected = selector.apply_science_pack_ingredient_policy({{"cryogenic-science-pack",2},{"space-science-pack",1}}, key)
    check(has(selected,"cryogenic-science-pack"), "Mandatory progression gate survives an opposing exclusion: " .. key)
    check(not has(selected,"space-science-pack"), "Retired optional science still excluded beside mandatory gate: " .. key)
  end
end)
policy_authority.science_roles_for_stream = original_roles
mods["space-is-fake"] = nil
data.raw.item["space-science-pack"].hidden = false
data.raw.recipe["space-science-pack"].hidden = false
data.raw.technology["space-science-pack"].enabled = true
settings.startup["mir-science-pack-ingredient-policy"] = {value="configured"}
context.with_active(context.new(), function()
  local selected = selector.pick_science_for_stream(streams.research_concrete, "research_concrete")
  check(has(selected,"space-science-pack"), "Ordinary space-science preference remains intact without Space Is Fake")
  for _, key in ipairs({"weapon-shooting-speed", "research-speed"}) do
    local final = continuation_qualifier.resolve_ingredients(defaults.base_extensions[key], {ingredients={{"automation-science-pack",2},{"utility-science-pack",3}}}, key)
    check(final and has(final,"space-science-pack"), "Ordinary continuation space science remains without Space Is Fake: " .. key)
  end
end)
print("MIR-COMMUNITY-HOTFIX-PASS " .. assertions)

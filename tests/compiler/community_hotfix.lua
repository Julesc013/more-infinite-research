-- Controlled current-source regressions. No native engine or ecosystem claim.
mods = {base = "2.1.20"}
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
local packs = {"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","military-science-pack","utility-science-pack","space-science-pack"}
for _, pack in ipairs(packs) do
  data.raw.item[pack] = {type="item",name=pack,stack_size=200}
  data.raw.technology[pack] = {type="technology",name=pack,enabled=true,effects={},unit={count=1,ingredients={{"automation-science-pack",1}},time=1}}
  data.raw.recipe[pack] = {type="recipe",name=pack,enabled=true,ingredients={},results={{type="item",name=pack,amount=1}},categories={"crafting"}}
end
data.raw.lab.lab = {type="lab",name="lab",inputs=packs}
data.raw.character = {character={type="character",name="character",crafting_categories={"crafting"}}}
mods["space-is-fake"] = "1.0.76"
mods["space-age"] = "2.1.20"
data.raw.item["space-science-pack"].hidden = true
data.raw.recipe["space-science-pack"].hidden = true
data.raw.technology["space-science-pack"].enabled = false
data.raw.technology["space-science-pack"].hidden = true
settings.startup["ips-require-space-gate"] = {value=false}
settings.startup["mir-lab-incompatibility-policy"] = {value="reduce"}
local modes = {"configured","space","space-and-promethium","space-age-progression","official-progression","all-official","all"}
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
  end)
end
mods["space-is-fake"] = nil
data.raw.item["space-science-pack"].hidden = false
data.raw.recipe["space-science-pack"].hidden = false
data.raw.technology["space-science-pack"].enabled = true
settings.startup["mir-science-pack-ingredient-policy"] = {value="configured"}
context.with_active(context.new(), function()
  local selected = selector.pick_science_for_stream(streams.research_concrete, "research_concrete")
  check(has(selected,"space-science-pack"), "Ordinary space-science preference remains intact without Space Is Fake")
end)
print("MIR-COMMUNITY-HOTFIX-PASS " .. assertions)

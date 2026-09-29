local technology_name = "recipe-prod-research_material_ric_coke-1"
local recipe_name = "ric-carbonise-marine-biomass"

local function fail(message)
  error("MIR RIC Marine carbonisation: " .. message)
end

local world = settings.startup["ric-world-mode"] and settings.startup["ric-world-mode"].value
local progression = settings.startup["ric-progression-mode"] and settings.startup["ric-progression-mode"].value
if progression ~= "space-age" then fail("fixture requires the exact Space Age progression mode") end
if world == "continental" then
  if data.raw.technology[technology_name] then fail("Marine-only technology appeared in Continental mode") end
  log("[MIR42_RIC_CONTINENTAL_DATA] PASS marine-technology=absent")
  return
elseif world ~= "marine" then
  fail("unknown RIC world mode")
end

local recipe = data.raw.recipe[recipe_name]
local technology = data.raw.technology[technology_name]
if not recipe or recipe.allow_productivity ~= true then fail("qualified route is absent or no longer permits productivity") end
if not technology or technology.max_level ~= "infinite" then
  fail("MIR owner must retain the lossless infinite prototype")
end
local transport = data.raw["mod-data"] and data.raw["mod-data"]["more-infinite-research-maximum-level-policy"]
local policy = transport and transport.data
if not policy or policy.schema ~= 3 or policy.finalizer_status ~= "accepted" then
  fail("MIR maximum-level policy is unavailable")
end
local cap_binding, cap_count = nil, 0
for _, binding in ipairs(policy.bindings or {}) do
  if binding.technology_id == technology_name then
    cap_binding, cap_count = binding, cap_count + 1
  end
end
if cap_count ~= 1 or cap_binding.cap.effective ~= 3
    or cap_binding.prototype_strategy.mode ~= "lossless-infinite-prototype"
    or cap_binding.runtime_strategy.mode ~= "absolute-cap-controller"
    or cap_binding.diagnostics.status ~= "accepted" then
  fail("three-level runtime cap binding differs")
end

local function amount(entries, name)
  for _, entry in ipairs(entries or {}) do
    if (entry.type or "item") == "item" and entry.name == name then return entry.amount end
  end
  return nil
end

if amount(recipe.ingredients, "ric-dried-marine-biomass") ~= 6
    or amount(recipe.results, "ric-coke") ~= 3
    or amount(recipe.results, "ric-ash") ~= 1 then
  fail("final carbonisation recipe changed")
end

local effects = {}
for _, effect in ipairs(technology.effects or {}) do
  if effect.type ~= "change-recipe-productivity" then fail("unexpected MIR effect type") end
  effects[#effects + 1] = effect
end
if #effects ~= 1 or effects[1].recipe ~= recipe_name or effects[1].change ~= 0.02 then
  fail("MIR must own only the exact carbonisation route at +2% per level")
end

local owners = {}
local withheld = {
  ["ric-mechanical-classify-marine-sediment"] = true,
  ["ric-brominated-flame-retardant"] = true,
  ["ric-wash-aluminous-marine-clay"] = true,
  ["ric-beneficiate-phosphatic-marine-sediment"] = true,
  ["ric-recover-fluorite-from-hydrothermal-gangue"] = true,
  ["ric-wash-polymetallic-nodules"] = true,
  ["ric-crush-hydrothermal-sulfide-rubble"] = true,
  ["ric-gravity-preconcentrate-hydrothermal-sulfides"] = true,
  ["ric-flotate-hydrothermal-sulfides"] = true,
  ["ric-wet-concentrate-heavy-mineral-sand"] = true,
  ["ric-magnetic-separate-titanium-minerals"] = true,
  ["ric-zircon-to-zirconia"] = true,
  ["ric-zirconia-refractory-brick"] = true,
  ["ric-deep-ocean-trace-metal-recovery"] = true,
  ["ric-separate-deep-ocean-refractory-metals"] = true,
  ["ric-amidoxime-adsorbent"] = true
}
for name, candidate in pairs(data.raw.technology) do
  for _, effect in ipairs(candidate.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      owners[#owners + 1] = name
    elseif effect.type == "change-recipe-productivity" and withheld[effect.recipe] then
      fail("unqualified Marine return-path recipe gained productivity: " .. effect.recipe)
    end
  end
end
if #owners ~= 1 or owners[1] ~= technology_name then fail("carbonisation productivity has another owner") end

local unlocked = false
for _, effect in ipairs((data.raw.technology["ric-coking"] or {}).effects or {}) do
  if effect.type == "unlock-recipe" and effect.recipe == recipe_name then unlocked = true end
end
if not unlocked then fail("RIC coking no longer unlocks carbonisation") end

log("[MIR42_RIC_MARINE_DATA] PASS technology=" .. technology_name ..
  " recipe=" .. recipe_name .. " change=0.02 runtime_cap=3 owner=unique")

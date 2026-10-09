local recipe_name = "bob-tin-plate"
local technology_name = "recipe-prod-research_material_tin-1"
local raw_direct_cap = 2
local imported_cap = 3
local profile_codec = require("__more-infinite-research__/prototypes/mir/settings/profile_codec")
local startup_settings = require("__more-infinite-research__/prototypes/mir/runtime/startup_settings")

local function fail(message)
  error("[mir-f200-bob-tin-production-gain] " .. message)
end

local function entry_name(entry) return entry and (entry.name or entry[1]) end
local function entry_amount(entry) return entry and (entry.amount or entry[2]) end
local function entry_type(entry) return entry and (entry.type or "item") end
local function contains(values, expected)
  for _, value in ipairs(values or {}) do if value == expected then return true end end
  return false
end

if mods["angelssmelting"] or mods["angelsrefining"] or mods["angelspetrochem"] then fail("F200 Bob-only production-gain fixture refuses Angel modules") end
local recipe = data.raw.recipe[recipe_name]
local categories = recipe and recipe.categories or nil
if not categories and recipe and recipe.category then categories = {recipe.category} end
if not recipe or #categories ~= 1 or categories[1] ~= "smelting" or recipe.normal or recipe.expensive then fail("exact F200 Bob Tin final recipe form differs") end
if #recipe.ingredients ~= 1 or entry_type(recipe.ingredients[1]) ~= "item" or entry_name(recipe.ingredients[1]) ~= "bob-tin-ore" or entry_amount(recipe.ingredients[1]) ~= 1 then fail("exact F200 Bob Tin input differs") end
if #recipe.results ~= 1 or entry_type(recipe.results[1]) ~= "item" or entry_name(recipe.results[1]) ~= "bob-tin-plate" or entry_amount(recipe.results[1]) ~= 1 then fail("exact F200 Bob Tin output differs") end
if recipe.allow_productivity ~= true or recipe.auto_recycle ~= false then fail("F200 Bob Tin productivity or recycling state differs") end
local furnace = data.raw.furnace["stone-furnace"]
if not furnace or not contains(furnace.crafting_categories, "smelting") then fail("F200 stone-furnace does not witness exact smelting capability") end

local technology = data.raw.technology[technology_name]
if not technology or technology.max_level ~= "infinite" then fail("F200 finite runtime Tin technology prototype differs") end
local owner_count = 0
local owner_change = nil
for owner_name, candidate in pairs(data.raw.technology) do
  for _, effect in ipairs(candidate.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      owner_count = owner_count + 1
      if owner_name ~= technology_name or effect.change ~= 0.02 then fail("F200 Tin productivity owner or exact change differs") end
      owner_change = effect.change
    end
  end
end
if owner_count ~= 1 then fail("F200 Bob Tin requires exactly one productivity owner") end

local profile = settings.startup["mir-settings-profile-import"]
local cap = settings.startup["ips-max-level-research_material_tin"]
if not profile or type(profile.value) ~= "string" or string.sub(profile.value, 1, 8) ~= "MIRSET1:" or not cap or cap.value ~= raw_direct_cap then fail("F200 distinguishable raw and MIRSET1 cap transport differs") end
local decoded, decode_error = profile_codec.decode(profile.value)
if not decoded or not decoded.settings or decoded.settings["ips-max-level-research_material_tin"] ~= imported_cap then fail("F200 MIRSET1 cap transport does not decode to level three: " .. tostring(decode_error)) end
if startup_settings.raw("ips-max-level-research_material_tin") ~= raw_direct_cap or startup_settings.get("ips-max-level-research_material_tin") ~= imported_cap then fail("F200 effective imported Tin cap does not override raw direct cap") end

log("[mir-f200-bob-tin-production-gain] DATA PASS recipe=" .. recipe.name .. " machine=" .. furnace.name .. " owner=" .. owner_count .. " change=" .. owner_change .. " raw=" .. startup_settings.raw("ips-max-level-research_material_tin") .. " imported=" .. decoded.settings["ips-max-level-research_material_tin"] .. " effective=" .. startup_settings.get("ips-max-level-research_material_tin"))

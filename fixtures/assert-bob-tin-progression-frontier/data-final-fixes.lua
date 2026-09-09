local anchor_name = "recipe-prod-research_material_tin-1"
local stream_key = "research_material_tin"
local recipe_name = "bob-tin-plate"
local profile_codec = require("__more-infinite-research__/prototypes/mir/settings/profile_codec")
local startup_settings = require("__more-infinite-research__/prototypes/mir/runtime/startup_settings")

local function fail(message) error("[mir-bob-tin-progression-frontier] " .. message) end

local function sorted(values)
  table.sort(values)
  return values
end

local function entry_name(entry) return entry and (entry.name or entry[1]) end
local function entry_amount(entry) return entry and (entry.amount or entry[2]) end
local function entry_type(entry) return entry and (entry.type or "item") end

local function normalized_entries(entries)
  local out = {}
  for _, entry in ipairs(entries or {}) do
    table.insert(out, {type = entry_type(entry), name = entry_name(entry), amount = entry_amount(entry)})
  end
  table.sort(out, function(left, right)
    local left_key = left.type .. "\0" .. left.name
    local right_key = right.type .. "\0" .. right.name
    return left_key < right_key
  end)
  return out
end

local function recipe_products(recipe)
  if recipe.results then return normalized_entries(recipe.results) end
  if recipe.result then return {{type = "item", name = recipe.result, amount = recipe.result_count or 1}} end
  return {}
end

local function produces(recipe, item)
  for _, product in ipairs(recipe_products(recipe)) do
    if product.type == "item" and product.name == item then return true end
  end
  return false
end

local function json_escape(value)
  return value:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
end

local function json(value)
  local kind = type(value)
  if kind == "string" then return "\"" .. json_escape(value) .. "\"" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then return tostring(value) end
  if kind ~= "table" then fail("unsupported canonical observation value " .. kind) end
  local count, array = 0, true
  for key, _ in pairs(value) do
    count = count + 1
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then array = false end
  end
  if array and #value == count then
    local parts = {}
    for index = 1, #value do parts[index] = json(value[index]) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys, parts = {}, {}
  for key, _ in pairs(value) do
    if type(key) ~= "string" then fail("canonical observation object key is not text") end
    table.insert(keys, key)
  end
  table.sort(keys)
  for _, key in ipairs(keys) do table.insert(parts, json(key) .. ":" .. json(value[key])) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function set_contains(values, expected)
  for _, value in ipairs(values or {}) do if value == expected then return true end end
  return false
end

for _, name in ipairs({"base", "elevated-rails", "quality", "recycler", "space-age", "boblibrary", "bobores", "bobplates", "more-infinite-research"}) do
  if not mods[name] then fail("required exact F210 Bob closure mod absent " .. name) end
end
for _, name in ipairs({"angelssmelting", "angelsrefining", "angelspetrochem"}) do
  if mods[name] then fail("Bob-only progression-frontier fixture refuses Angel module " .. name) end
end

local anchor = data.raw.technology[anchor_name]
if not anchor then fail("Tin anchor technology is absent") end
local owner_count, owner_change = 0, nil
for technology_name, technology in pairs(data.raw.technology) do
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      owner_count = owner_count + 1
      if technology_name ~= anchor_name then fail("Tin productivity owner differs " .. technology_name) end
      owner_change = effect.change
    end
  end
end
if owner_count ~= 1 or owner_change == nil then fail("Tin anchor requires exactly one productivity owner") end

local raw_cap = startup_settings.raw("ips-max-level-" .. stream_key)
local effective_cap = startup_settings.get("ips-max-level-" .. stream_key)
local profile = settings.startup["mir-settings-profile-import"]
if not profile or type(profile.value) ~= "string" then fail("MIRSET1 profile is absent") end
local decoded, profile_error = profile_codec.decode(profile.value)
local imported_cap = decoded and decoded.settings and decoded.settings["ips-max-level-" .. stream_key]
if not decoded or imported_cap == nil then fail("MIRSET1 profile does not decode: " .. tostring(profile_error)) end

local candidate_packs, candidate_pack_types = {}, {}
local function default_enabled(recipe) return recipe.enabled ~= false end
if not default_enabled({}) or default_enabled({enabled = false}) then fail("raw recipe enabled normalization drift") end
local function resolve_technology_ingredient_prototype_type(ingredient)
  if ingredient.type ~= "item" then fail("technology unit ingredient has unsupported type " .. tostring(ingredient.type)) end
  local matches = {}
  for _, prototype_type in ipairs({"item", "tool"}) do
    if (data.raw[prototype_type] or {})[ingredient.name] then table.insert(matches, prototype_type) end
  end
  if #matches ~= 1 then fail("technology unit ingredient lacks exact item or tool prototype binding " .. ingredient.name) end
  return matches[1]
end
for _, technology in pairs(data.raw.technology or {}) do
  for _, ingredient in ipairs(normalized_entries((technology.unit or {}).ingredients)) do
    local prototype_type = resolve_technology_ingredient_prototype_type(ingredient)
    if not candidate_pack_types[ingredient.name] then
      candidate_pack_types[ingredient.name] = prototype_type
    local producers, enabled_producers = {}, {}
    for recipe_id, recipe in pairs(data.raw.recipe or {}) do
      if produces(recipe, ingredient.name) then
        table.insert(producers, recipe_id)
        if default_enabled(recipe) then table.insert(enabled_producers, recipe_id) end
      end
    end
    sorted(producers); sorted(enabled_producers)
    local producer_set, unlockers = {}, {}
    for _, recipe_id in ipairs(producers) do producer_set[recipe_id] = true end
    for technology_id, technology in pairs(data.raw.technology) do
      for _, effect in ipairs(technology.effects or {}) do
        if effect.type == "unlock-recipe" and producer_set[effect.recipe] then table.insert(unlockers, technology_id); break end
      end
    end
    sorted(unlockers)
    table.insert(candidate_packs, {
      name = ingredient.name,
      prototype_type = prototype_type,
      producer_recipe_ids = producers,
      default_enabled_producer_recipe_ids = enabled_producers,
      direct_unlock_technology_ids = unlockers
    })
    end
  end
end
table.sort(candidate_packs, function(left, right) return left.name < right.name end)

local ingredient_names, present_non_hidden_labs, compatible_labs = {}, {}, {}
for _, ingredient in ipairs(normalized_entries((anchor.unit or {}).ingredients)) do ingredient_names[ingredient.name] = true end
for lab_id, lab in pairs(data.raw.lab or {}) do
  local inputs = sorted((function()
    local values = {}
    for _, input in ipairs(lab.inputs or {}) do table.insert(values, input) end
    return values
  end)())
  local compatible = true
  for name, _ in pairs(ingredient_names) do if not set_contains(inputs, name) then compatible = false end end
  if lab.hidden ~= true then
    table.insert(present_non_hidden_labs, {id = lab_id, inputs = inputs})
    if compatible then table.insert(compatible_labs, lab_id) end
  end
end
table.sort(present_non_hidden_labs, function(left, right) return left.id < right.id end)
sorted(compatible_labs)

local observation = {
  anchor = {
    stream_key = stream_key,
    technology = anchor_name,
    effect_type = "change-recipe-productivity",
    effect_recipe = recipe_name,
    effect_change_per_completed_level = owner_change,
    exact_owner_count = owner_count,
    prototype_max_level = anchor.max_level,
    prerequisites = sorted((function() local values = {}; for _, name in ipairs(anchor.prerequisites or {}) do table.insert(values, name) end; return values end)()),
    science_ingredients = normalized_entries((anchor.unit or {}).ingredients),
    cap_transport = {raw_direct_max_level = raw_cap, mirset1_imported_max_level = imported_cap, effective_max_level = effective_cap}
  },
  science_lab_frontier = {
    candidate_selection_rule = "all-final-technology-unit-ingredients-with-exact-item-or-tool-prototype-binding",
    raw_recipe_enabled_semantics = "enabled-not-false",
    candidate_science_packs = candidate_packs,
    present_non_hidden_lab_prototypes = present_non_hidden_labs,
    anchor_compatible_present_non_hidden_lab_ids = compatible_labs
  },
  companion_continuation = {stable_id_allocation = "blocked", emission = "blocked", reason = "diagnostic-establishes-inputs-only"}
}
log("[mir-bob-tin-progression-frontier] DATA JSON " .. json(observation))

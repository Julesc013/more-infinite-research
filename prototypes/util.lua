
local C = require("prototypes.config")
local defaults = require("defaults")
local U = {}

local function deepcopy(value)
  if table.deepcopy then return table.deepcopy(value) end
  local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do
      out[copy(k)] = copy(vv)
    end
    return out
  end
  return copy(value)
end

local function has_tech(name) return (data.raw.technology or {})[name] ~= nil end

local ITEM_TYPES = {
  "item",
  "tool",
  "module",
  "ammo",
  "capsule",
  "gun",
  "armor",
  "repair-tool",
  "item-with-entity-data",
  "item-with-inventory",
  "item-with-label",
  "item-with-tags",
  "selection-tool",
  "blueprint",
  "blueprint-book",
  "deconstruction-item",
  "upgrade-item",
  "spidertron-remote",
  "rail-planner",
  "space-platform-starter-pack"
}

function U.item_prototype(name)
  if not name then return nil end
  for _, type_name in ipairs(ITEM_TYPES) do
    local bucket = data.raw[type_name]
    if bucket and bucket[name] then return bucket[name] end
  end
  return nil
end

local function each_item_prototype(callback)
  for _, type_name in ipairs(ITEM_TYPES) do
    for name, prototype in pairs(data.raw[type_name] or {}) do
      callback(name, prototype, type_name)
    end
  end
end

local lab_inputs_cache = nil

function U.all_lab_inputs()
  if lab_inputs_cache then return deepcopy(lab_inputs_cache) end
  local out, seen = {}, {}
  for _, lab in pairs(data.raw.lab or {}) do
    for _, input in ipairs(lab.inputs or {}) do
      if not seen[input] and U.item_prototype(input) then
        seen[input] = true
        table.insert(out, input)
      end
    end
  end
  table.sort(out)
  lab_inputs_cache = out
  return deepcopy(out)
end

function U.science_pack_exists(name)
  if not U.item_prototype(name) then return false end
  for _, input in ipairs(U.all_lab_inputs()) do
    if input == name then return true end
  end
  return false
end

local function ingredient_name(ingredient)
  if not ingredient then return nil end
  return ingredient.name or ingredient[1]
end

local function ingredient_amount(ingredient)
  if not ingredient then return 1 end
  return ingredient.amount or ingredient[2] or 1
end

local function lab_accepts_all(lab, packs)
  local accepted = {}
  for _, input in ipairs((lab and lab.inputs) or {}) do
    accepted[input] = true
  end
  for _, pack in ipairs(packs or {}) do
    if not accepted[pack] then return false end
  end
  return true
end

function U.any_lab_accepts_all(packs)
  if not packs or #packs == 0 then return false end
  for _, lab in pairs(data.raw.lab or {}) do
    if lab_accepts_all(lab, packs) then return true end
  end
  return false
end

function U.valid_research_ingredients(ingredients)
  local packs = {}
  for _, ingredient in ipairs(ingredients or {}) do
    local name = ingredient_name(ingredient)
    if name then table.insert(packs, name) end
  end
  return U.any_lab_accepts_all(packs)
end

function U.best_lab_compatible_ingredients(ingredients, context)
  local source = deepcopy(ingredients or {})
  if #source == 0 then return nil, "empty" end
  if U.valid_research_ingredients(source) then return source, nil end

  local labs = {}
  for name, lab in pairs(data.raw.lab or {}) do
    table.insert(labs, {name = name, lab = lab})
  end
  table.sort(labs, function(a, b) return a.name < b.name end)

  local best = nil
  local best_lab = nil
  for _, entry in ipairs(labs) do
    local candidate = {}
    local accepted = {}
    for _, input in ipairs(entry.lab.inputs or {}) do accepted[input] = true end
    for _, ingredient in ipairs(source) do
      local name = ingredient_name(ingredient)
      if name and accepted[name] then
        table.insert(candidate, {name, ingredient_amount(ingredient)})
      end
    end
    if #candidate > 0 and U.valid_research_ingredients(candidate) then
      if not best or #candidate > #best then
        best = candidate
        best_lab = entry.name
      end
    end
  end

  if best then
    log("[more-infinite-research] Reduced science packs for " .. tostring(context or "unknown technology") .. " to a lab-compatible subset accepted by " .. best_lab .. ".")
    return best, "reduced"
  end

  log("[more-infinite-research] No lab can research the selected science packs for " .. tostring(context or "unknown technology") .. ".")
  return nil, "invalid"
end

function U.is_space_age() return mods and mods["space-age"] ~= nil end

local function startup_setting(name)
  local s = settings and settings.startup and settings.startup[name]
  if s then return s.value end
  return nil
end

local function ensure_minimum(value, fallback, minimum)
  minimum = minimum or 0
  if type(value) ~= "number" then return fallback end
  if value < minimum then return fallback end
  return value
end

local function lookup_default(key, field, spec, fallback)
  local stream_defaults = defaults.streams and defaults.streams[key]
  if stream_defaults and stream_defaults[field] ~= nil then return stream_defaults[field] end
  if spec and spec[field] ~= nil then return spec[field] end
  local shared_defaults = defaults.shared or {}
  if shared_defaults[field] ~= nil then return shared_defaults[field] end
  return fallback
end

local function default_base_cost_for(key, spec)
  return lookup_default(key, "base_cost", spec, C.shared.base_cost)
end

local function default_growth_for(key, spec)
  return lookup_default(key, "growth_factor", spec, C.shared.growth_factor)
end

local function default_max_for(key, spec)
  return lookup_default(key, "max_level", spec, nil)
end

local function default_research_time_for(key, spec)
  return lookup_default(key, "research_time", spec, C.shared.research_time)
end

local function default_enabled_for(key, spec)
  return lookup_default(key, "enabled", spec, true)
end

function U.enabled_for(key, spec)
  local s = settings and settings.startup and settings.startup["ips-enable-"..key]
  if s ~= nil then return s.value end
  return default_enabled_for(key, spec)
end

function U.base_cost_for(key, spec)
  local default = default_base_cost_for(key, spec)
  local value = startup_setting("ips-cost-base-"..key)
  if value ~= nil then return ensure_minimum(value, default, 1) end
  return ensure_minimum(default, C.shared.base_cost, 1)
end

function U.growth_factor_for(key, spec)
  local default = default_growth_for(key, spec)
  local value = startup_setting("ips-cost-growth-"..key)
  if value ~= nil then return ensure_minimum(value, default, 1) end
  return ensure_minimum(default, C.shared.growth_factor, 1)
end

function U.research_time_for(key, spec)
  local default = ensure_minimum(default_research_time_for(key, spec), C.shared.research_time, 1)
  local value = startup_setting("ips-research-time-"..key)
  if value ~= nil then
    if value <= 0 then return default end
    return ensure_minimum(value, default, 1)
  end
  return default
end

local function coerce_max_level(value)
  if value == nil then return nil end
  if value == "infinite" then return "infinite" end
  if type(value) == "number" then
    if value <= 0 then return "infinite" end
    return math.floor(value)
  end
  if type(value) == "string" then
    local num = tonumber(value)
    if not num then return "infinite" end
    if num <= 0 then return "infinite" end
    return math.floor(num)
  end
  return "infinite"
end

function U.max_level_for(key, spec)
  local setting_value = startup_setting("ips-max-level-"..key)
  if setting_value ~= nil then
    if setting_value <= 0 then return "infinite" end
    return math.floor(setting_value)
  end
  local from_spec = coerce_max_level(default_max_for(key, spec))
  if from_spec ~= nil then return from_spec end
  return "infinite"
end

local function icons_from_tech(name)
  local t = (data.raw.technology or {})[name]
  if not t then return nil end
  if t.icons then return t.icons end
  if t.icon then return { {icon=t.icon, icon_size=t.icon_size or 64} } end
  return nil
end
local function icon_from_item(name)
  local it = U.item_prototype(name)
  if not it then return nil end
  if it.icons then return it.icons end
  if it.icon then return { {icon=it.icon, icon_size=it.icon_size or 64} } end
  return nil
end
function U.icons_for_stream(stream)
  if stream.icons then
    return deepcopy(stream.icons)
  end
  if stream.icon then
    local entry = { icon = stream.icon, icon_size = stream.icon_size or 64 }
    if stream.icon_mipmaps then entry.icon_mipmaps = stream.icon_mipmaps end
    if stream.icon_tint then entry.tint = stream.icon_tint end
    return { entry }
  end
  if stream.icon_tech then
    local ic = icons_from_tech(stream.icon_tech)
    if ic then return ic end
  end
  local src = stream.icon_item or ((stream.items or {})[1])
  return icon_from_item(src) or { { icon="__base__/graphics/technology/mining-productivity.png", icon_size=256 } }
end

local VANILLA_PACK_ORDER = {
  "automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack",
  "military-science-pack","utility-science-pack","space-science-pack",
    "agricultural-science-pack","metallurgic-science-pack","electromagnetic-science-pack","cryogenic-science-pack","promethium-science-pack"
}

local EXTRA = {
  research_concrete            = { "space-science-pack" },
  research_furnace             = { "metallurgic-science-pack" },
  research_mining_drill        = { "metallurgic-science-pack" },
  research_walls               = { "military-science-pack", "space-science-pack" },
  research_grenades            = { "military-science-pack", "space-science-pack" },
  research_rails               = { "space-science-pack" },
  research_electric_energy     = { "electromagnetic-science-pack" },

  research_breeding            = { "agricultural-science-pack" },
  research_plastic             = { "agricultural-science-pack" },
  research_rocket_fuel         = { "agricultural-science-pack" },
  research_bioflux             = { "agricultural-science-pack" },
  research_carbon_fiber        = { "agricultural-science-pack" },
  research_rockets             = { "agricultural-science-pack", "military-science-pack" },

  research_sulfur              = { "metallurgic-science-pack" },
  research_explosives          = { "metallurgic-science-pack" },
  research_low_density_structure = { "metallurgic-science-pack" },
  research_engine              = { "metallurgic-science-pack" },
  research_tungsten            = { "metallurgic-science-pack" },

  research_batteries           = { "electromagnetic-science-pack" },
  research_electronic_circuit  = { "electromagnetic-science-pack" },
  research_advanced_circuit    = { "electromagnetic-science-pack" },
  research_processing_unit     = { "electromagnetic-science-pack" },
  research_electric_engine     = { "electromagnetic-science-pack" },
  research_flying_robot_frame  = { "electromagnetic-science-pack" },
  research_holmium             = { "electromagnetic-science-pack" },
  research_supercapacitor      = { "electromagnetic-science-pack" },
  research_superconductor      = { "electromagnetic-science-pack" },

  research_lithium             = { "cryogenic-science-pack" },
  research_quantum_processor   = { "cryogenic-science-pack" },
  research_modules             = { "cryogenic-science-pack" },

  research_belts               = { "space-science-pack" },
  research_inserters           = { "space-science-pack" },
  research_bullets             = { "military-science-pack", "space-science-pack" },

  research_inventory_capacity  = { "agricultural-science-pack" },
  research_character_trash_slots = { "agricultural-science-pack" },
  research_robot_battery       = { "space-science-pack" },
  research_science_pack_productivity = {}
}

local function add_if_science_pack_exists(list, name)
  if U.science_pack_exists(name) then table.insert(list, name) end
end
local function merge_lists(a, b)
  local out = {}
  if a then for _,v in ipairs(a) do table.insert(out, v) end end
  if b then for _,v in ipairs(b) do table.insert(out, v) end end
  if #out == 0 then return nil end
  return out
end

function U.pick_science_for_stream(spec, key)
  local packs = {}
  local desired = spec and spec.science_packs
  if desired == "all" then
    for _,p in ipairs(U.pack_list_all()) do add_if_science_pack_exists(packs, p) end
  elseif type(desired) == "table" then
    for _,p in ipairs(desired) do add_if_science_pack_exists(packs, p) end
  elseif type(desired) == "string" then
    local list = U.pack_list_for_extension(key, desired)
    if not list then list = U.pack_list_for_extension(desired) end
    if list then for _,p in ipairs(list) do add_if_science_pack_exists(packs, p) end end
  elseif key == "research_science_pack_productivity" then
    for _,p in ipairs(U.pack_list_all()) do add_if_science_pack_exists(packs, p) end
  else
    for _,p in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}) do add_if_science_pack_exists(packs, p) end
    for _,p in ipairs(EXTRA[key] or {}) do add_if_science_pack_exists(packs, p) end
  end
  local out, seen = {}, {}
  for _,n in ipairs(packs) do if not seen[n] then seen[n]=true; table.insert(out, {n,1}) end end
  return out
end

function U.pack_list_all()
  local available = {}
  for _, pack in ipairs(U.all_lab_inputs()) do
    available[pack] = true
  end

  local out = {}
  for _, pack in ipairs(VANILLA_PACK_ORDER) do
    if available[pack] then
      table.insert(out, pack)
      available[pack] = nil
    end
  end

  local extra = {}
  for pack, _ in pairs(available) do table.insert(extra, pack) end
  table.sort(extra)
  for _, pack in ipairs(extra) do table.insert(out, pack) end
  return out
end

function U.pack_list_for_extension(key, desired)
  if desired == "all" then
    return U.pack_list_all()
  end
  if type(desired) == "table" then
    local out = {}
    for _, name in ipairs(desired) do table.insert(out, name) end
    return out
  end
  local map = {
    ["braking-force"] = { "automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","space-science-pack" },
    ["research-speed"] = "all",
    ["worker-robots-storage"] = { "automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","utility-science-pack","electromagnetic-science-pack" },
    ["inserter-capacity-bonus"] = { "automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","agricultural-science-pack" },
    ["weapon-shooting-speed"] = { "automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","military-science-pack","space-science-pack" },
    ["laser-shooting-speed"] = { "automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","military-science-pack","space-science-pack" },
    ["research_electric_shooting_speed"] = { "automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","military-science-pack","electromagnetic-science-pack" },
    ["research_flamethrower_shooting_speed"] = { "automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","military-science-pack","space-science-pack" },
    ["research_rocket_shooting_speed"] = { "automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","military-science-pack","agricultural-science-pack" }
  }
  local list = map[key]
  if not list then return nil end
  if list == "all" then return U.pack_list_all() end
  return deepcopy(list)
end

local function recipe_outputs_item(recipe, item_name)
  local function matches(result)
    if not result then return false end
    local name = result.name or result[1] or result
    return name == item_name
  end
  local function scan(def)
    if not def then return false end
    if def.results then
      for _, result in pairs(def.results) do
        if matches(result) then return true end
      end
    elseif def.result then
      return matches(def.result)
    end
    return false
  end
  if recipe.normal or recipe.expensive then
    return scan(recipe.normal) or scan(recipe.expensive)
  end
  return scan(recipe)
end

local science_pack_unlock_cache = nil

local function build_science_pack_unlock_cache()
  if science_pack_unlock_cache then return science_pack_unlock_cache end
  science_pack_unlock_cache = {}
  local lab_inputs = U.all_lab_inputs()
  for tech_name, tech in pairs(data.raw.technology or {}) do
    for _, effect in ipairs(tech.effects or {}) do
      if effect.type == "unlock-recipe" and effect.recipe then
        local recipe = (data.raw.recipe or {})[effect.recipe]
        if recipe then
          for _, pack_name in ipairs(lab_inputs) do
            if recipe_outputs_item(recipe, pack_name) and not science_pack_unlock_cache[pack_name] then
              science_pack_unlock_cache[pack_name] = tech_name
            end
          end
        end
      end
    end
  end
  return science_pack_unlock_cache
end

function U.prereq_tech_for_science_pack(pack_name)
  if has_tech(pack_name) then return pack_name end
  local cache = build_science_pack_unlock_cache()
  local tech_name = cache[pack_name]
  if tech_name and has_tech(tech_name) then return tech_name end
  return nil
end

function U.build_prereqs_for(key, ingredients)
  local packs = ingredients or U.best_lab_compatible_ingredients(U.pick_science_for_stream(C.streams[key], key), key)
  local reqs, seen = {}, {}
  local function add(t) if t and has_tech(t) and not seen[t] then seen[t]=true; table.insert(reqs,t) end end
  for _,pair in ipairs(packs or {}) do
    local pack_name = pair[1]
    local prereq = U.prereq_tech_for_science_pack(pack_name)
    add(prereq)
  end
  local gate_on = (settings and settings.startup and settings.startup["ips-require-space-gate"] and settings.startup["ips-require-space-gate"].value) ~= false
  if gate_on then
    local PROM = "promethium-science-pack"
    local SPACE = "space-science-pack"
    if U.is_space_age() and U.science_pack_exists(PROM) then
      add(U.prereq_tech_for_science_pack(PROM))
    elseif U.science_pack_exists(SPACE) then
      add(U.prereq_tech_for_science_pack(SPACE))
    end
  end
  return reqs
end

local function recipe_outputs(rec)
  local out = {}
  local function push(p) if p then out[p.name or p[1]] = true end end
  local function scan(def)
    if not def then return end
    if def.results then for _,pp in pairs(def.results) do push(pp) end
    elseif def.result then push({def.result}) end
  end
  if rec.normal or rec.expensive then scan(rec.normal); scan(rec.expensive) else scan(rec) end
  return out
end

local DEFAULT_SKIP_CATEGORIES = {
  recycling = true
}

local function recipe_categories(recipe)
  if recipe.categories then return recipe.categories end
  if recipe.category then return {recipe.category} end
  return {"crafting"}
end

local function recipe_is_hidden(recipe)
  if recipe.hidden then return true end
  if recipe.normal and recipe.normal.hidden then return true end
  if recipe.expensive and recipe.expensive.hidden then return true end
  return false
end

local function has_category(recipe, categories)
  if not categories then return false end
  local wanted = {}
  for _, category in ipairs(categories) do wanted[category] = true end
  for _, category in ipairs(recipe_categories(recipe)) do
    if wanted[category] then return true end
  end
  return false
end

local function name_matches(name, patterns)
  for _, pattern in ipairs(patterns or {}) do
    if string.find(name, pattern) then return true end
  end
  return false
end

function U.matches_stream_recipe_filter(recipe_name, recipe, stream)
  local match = stream and stream.match
  if not match then return false end
  return has_category(recipe, match.categories) or name_matches(recipe_name, match.name_patterns)
end

local recipe_uses_blocked_ingredient

local function should_skip_recipe(recipe_name, recipe, options)
  if options.exclude_recipe_patterns and name_matches(recipe_name, options.exclude_recipe_patterns) then
    return true
  end
  if recipe_uses_blocked_ingredient(recipe, options.exclude_ingredient_patterns) then
    return true
  end
  if recipe_is_hidden(recipe) and not options.include_hidden then
    return true
  end
  if not options.include_recycling then
    for _, category in ipairs(recipe_categories(recipe)) do
      if DEFAULT_SKIP_CATEGORIES[category] then return true end
    end
  end
  return false
end

recipe_uses_blocked_ingredient = function(rec, patterns)
  if not patterns then return false end
  local function matches(name)
    for _,pat in ipairs(patterns) do
      if string.find(name, pat) then return true end
    end
    return false
  end
  local function scan(def)
    if not def or not def.ingredients then return false end
    for _,ing in pairs(def.ingredients) do
      local name = ing.name or ing[1]
      if name and matches(name) then return true end
    end
    return false
  end
  if rec.normal or rec.expensive then
    if scan(rec.normal) then return true end
    if scan(rec.expensive) then return true end
  else
    if scan(rec) then return true end
  end
  return false
end

local function gather_by_items(items, patterns, options)
  local want = {}
  options = options or {}
  if items then for _,n in ipairs(items) do want[n]=true end end
  if options.extra_outputs then for _,n in ipairs(options.extra_outputs) do want[n]=true end end
  if patterns then
    each_item_prototype(function(iname)
      for _,pat in ipairs(patterns) do
        if string.find(iname, pat) then want[iname]=true end
      end
    end)
  end
  local strict_rail = want["rail"] == true
  local seen, list = {}, {}
  for rname, r in pairs(data.raw.recipe or {}) do
    local skip = should_skip_recipe(rname, r, options)
    if not skip then
      local outs = recipe_outputs(r)
      local match = false
      for it,_ in pairs(want) do
        if strict_rail then
          if it == "rail" and outs["rail"] then match=true; break end
        else
          if outs[it] then match=true; break end
        end
      end
      if not match and options.match_stream and options.match_mode == "by_category_or_match" then
        match = U.matches_stream_recipe_filter(rname, r, options.match_stream)
      end
      if match and not seen[rname] then seen[rname]=true; table.insert(list, rname) end
    end
  end
  table.sort(list)
  return list
end

function U.recipes_for_stream(spec)
  if spec.groups then
    local buckets = {}
    for _,g in ipairs(spec.groups) do
      local list = gather_by_items(g.items, g.item_patterns, {
        extra_outputs = g.extra_outputs,
        exclude_recipe_patterns = merge_lists(spec.exclude_recipe_patterns, g.exclude_recipe_patterns),
        exclude_ingredient_patterns = merge_lists(spec.exclude_ingredient_patterns, g.exclude_ingredient_patterns),
        include_hidden = spec.include_hidden or g.include_hidden,
        include_recycling = spec.include_recycling or g.include_recycling,
        match_mode = g.mode or spec.mode,
        match_stream = g.match and g or spec
      })
      if #list > 0 then table.insert(buckets, {change=g.change or C.shared.per_level_default, recipes=list}) end
    end
    return buckets
  else
    local list = gather_by_items(spec.items, spec.item_patterns, {
      extra_outputs = spec.extra_outputs,
      exclude_recipe_patterns = spec.exclude_recipe_patterns,
      exclude_ingredient_patterns = spec.exclude_ingredient_patterns,
      include_hidden = spec.include_hidden,
      include_recycling = spec.include_recycling,
      match_mode = spec.mode,
      match_stream = spec
    })
    return { {change=C.shared.per_level_default, recipes=list} }
  end
end

return U

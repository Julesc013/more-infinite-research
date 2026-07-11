local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local recipe_facts = require("prototypes.mir.index.recipe_facts")

local R = {}

local DEFAULT_SKIP_CATEGORIES = {
  recycling = true
}

local function merge_lists(a, b)
  local out = {}
  if a then for _, v in ipairs(a) do table.insert(out, v) end end
  if b then for _, v in ipairs(b) do table.insert(out, v) end end
  if #out == 0 then return nil end
  return out
end

local function recipe_categories(recipe)
  return recipe.categories or {"crafting"}
end

local function recipe_is_hidden(recipe)
  return recipe.hidden == true
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

function R.matches_stream_recipe_filter(recipe_name, recipe, stream)
  local match = stream and stream.match
  if not match then return false end
  return has_category(recipe, match.categories)
    or name_matches(recipe_name, match.name_patterns)
    or name_matches(recipe_name, match.recipe_patterns)
end

local function recipe_uses_blocked_ingredient(rec, patterns)
  if not patterns then return false end
  local function matches(name)
    for _, pat in ipairs(patterns) do
      if string.find(name, pat) then return true end
    end
    return false
  end
  for _, name in ipairs(rec.ingredient_names or {}) do
    if matches(name) then return true end
  end
  return false
end

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

local function add_wanted_outputs(want, names)
  for _, name in ipairs(names or {}) do
    want[name] = true
  end
end

local function add_pattern_outputs(want, patterns, iterator)
  if not patterns then return end
  iterator(function(name)
    for _, pat in ipairs(patterns) do
      if string.find(name, pat) then want[name] = true end
    end
  end)
end

local function add_module_outputs(want, options)
  local tiers = options.module_tiers
  local tier_set = nil
  if type(tiers) == "table" then
    tier_set = {}
    for _, tier in ipairs(tiers) do tier_set[tonumber(tier)] = true end
  end
  local minimum = tonumber(options.module_tier_min)
  local maximum = tonumber(options.module_tier_max)
  if not tier_set and minimum == nil and maximum == nil then return end
  for name, module in pairs(data_raw.prototypes("module")) do
    local tier = type(module) == "table" and tonumber(module.tier) or nil
    if tier
      and (not tier_set or tier_set[tier])
      and (minimum == nil or tier >= minimum)
      and (maximum == nil or tier <= maximum)
    then
      want[name] = true
    end
  end
end

local function gather_by_items(items, patterns, options)
  local want = {}
  options = options or {}
  add_wanted_outputs(want, items)
  add_wanted_outputs(want, options.fluids)
  add_wanted_outputs(want, options.extra_outputs)
  add_pattern_outputs(want, patterns, lookup.each_item_prototype)
  add_pattern_outputs(want, options.fluid_patterns, lookup.each_fluid_prototype)
  add_module_outputs(want, options)
  local candidate_categories, candidate_patterns = {}, {}
  local stream_match = options.match_stream and options.match_stream.match
  if options.match_mode == "by_category_or_match" and stream_match then
    for _, category in ipairs(stream_match.categories or {}) do table.insert(candidate_categories, category) end
    for _, pattern in ipairs(stream_match.name_patterns or {}) do table.insert(candidate_patterns, pattern) end
    for _, pattern in ipairs(stream_match.recipe_patterns or {}) do table.insert(candidate_patterns, pattern) end
  end
  for _, pattern in ipairs(options.recipe_patterns or {}) do table.insert(candidate_patterns, pattern) end

  local seen, list = {}, {}
  for _, rname in ipairs(recipe_facts.candidate_names(want, candidate_categories, candidate_patterns)) do
    local r = recipe_facts.get(rname)
    if not should_skip_recipe(rname, r, options) then
      local outs = {}
      for _, output_name in ipairs(r.result_names or {}) do outs[output_name] = true end
      local match = false
      for it, _ in pairs(want) do
        if it == "rail" then
          if outs.rail then match = true; break end
        elseif outs[it] then
          match = true
          break
        end
      end
      if not match and options.match_stream and options.match_mode == "by_category_or_match" then
        match = R.matches_stream_recipe_filter(rname, r, options.match_stream)
      end
      if not match and options.recipe_patterns and name_matches(rname, options.recipe_patterns) then
        match = true
      end
      if match and not seen[rname] then
        seen[rname] = true
        table.insert(list, rname)
      end
    end
  end
  table.sort(list)
  return list
end

function R.recipes_for_stream(spec, per_level_default)
  if spec.groups then
    local buckets, assigned = {}, {}
    for _, g in ipairs(spec.groups) do
      local list = gather_by_items(g.items, g.item_patterns, {
        fluids = g.fluids,
        fluid_patterns = merge_lists(spec.fluid_patterns, g.fluid_patterns),
        extra_outputs = g.extra_outputs,
        recipe_patterns = merge_lists(spec.recipe_patterns, g.recipe_patterns),
        exclude_recipe_patterns = merge_lists(spec.exclude_recipe_patterns, g.exclude_recipe_patterns),
        exclude_ingredient_patterns = merge_lists(spec.exclude_ingredient_patterns, g.exclude_ingredient_patterns),
        include_hidden = spec.include_hidden or g.include_hidden,
        include_recycling = spec.include_recycling or g.include_recycling,
        module_tiers = g.module_tiers,
        module_tier_min = g.module_tier_min,
        module_tier_max = g.module_tier_max,
        match_mode = g.mode or spec.mode,
        match_stream = g.match and g or spec
      })
      local filtered = {}
      for _, recipe_name in ipairs(list) do
        -- Groups are ordered from broad/common to niche/high tier. If a later
        -- pattern also sees a recipe, keep the first tier assignment.
        if not assigned[recipe_name] then
          assigned[recipe_name] = true
          table.insert(filtered, recipe_name)
        end
      end
      if #filtered > 0 then
        table.insert(buckets, {change = g.change or per_level_default, recipes = filtered})
      end
    end
    return buckets
  end

  local list = gather_by_items(spec.items, spec.item_patterns, {
    fluids = spec.fluids,
    fluid_patterns = spec.fluid_patterns,
    extra_outputs = spec.extra_outputs,
    recipe_patterns = spec.recipe_patterns,
    exclude_recipe_patterns = spec.exclude_recipe_patterns,
    exclude_ingredient_patterns = spec.exclude_ingredient_patterns,
    include_hidden = spec.include_hidden,
    include_recycling = spec.include_recycling,
    module_tiers = spec.module_tiers,
    module_tier_min = spec.module_tier_min,
    module_tier_max = spec.module_tier_max,
    match_mode = spec.mode,
    match_stream = spec
  })
  return {{change = per_level_default, recipes = list}}
end

return R

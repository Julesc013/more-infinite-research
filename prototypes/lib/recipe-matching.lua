local lookup = require("prototypes.lib.prototype-lookup")

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

local function recipe_outputs(rec)
  local out = {}
  local function push(p)
    if not p then return end
    local name = type(p) == "string" and p or p.name or p[1]
    if name then out[name] = true end
  end
  local function scan(def)
    if not def then return end
    if def.results then
      for _, pp in pairs(def.results) do push(pp) end
    elseif def.result then
      push(def.result)
    end
  end
  if rec.normal or rec.expensive then
    scan(rec.normal)
    scan(rec.expensive)
  else
    scan(rec)
  end
  return out
end

local function recipe_categories(recipe)
  -- Factorio 2.1 can expose multiple categories; older prototypes used one.
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
  local function scan(def)
    if not def or not def.ingredients then return false end
    for _, ing in pairs(def.ingredients) do
      local name = type(ing) == "string" and ing or ing.name or ing[1]
      if name and matches(name) then return true end
    end
    return false
  end
  if rec.normal or rec.expensive then
    return scan(rec.normal) or scan(rec.expensive)
  end
  return scan(rec)
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

local function gather_by_items(items, patterns, options)
  local want = {}
  options = options or {}
  add_wanted_outputs(want, items)
  add_wanted_outputs(want, options.fluids)
  add_wanted_outputs(want, options.extra_outputs)
  add_pattern_outputs(want, patterns, lookup.each_item_prototype)
  add_pattern_outputs(want, options.fluid_patterns, lookup.each_fluid_prototype)
  local seen, list = {}, {}
  for rname, r in pairs(data.raw.recipe or {}) do
    if not should_skip_recipe(rname, r, options) then
      local outs = recipe_outputs(r)
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
    match_mode = spec.mode,
    match_stream = spec
  })
  return {{change = per_level_default, recipes = list}}
end

return R

local P = {}

local function append_list(dst, field, values)
  if not values then return end

  dst[field] = dst[field] or {}
  for _, value in ipairs(values) do
    table.insert(dst[field], value)
  end
end

local function append_groups(dst, groups)
  if not groups then return end

  dst.groups = dst.groups or {}
  for _, group in ipairs(groups) do
    table.insert(dst.groups, group)
  end
end

local function patch_stream(dst, patch)
  append_list(dst, "items", patch.append_items)
  append_list(dst, "item_patterns", patch.append_item_patterns)
  append_list(dst, "recipe_patterns", patch.append_recipe_patterns)
  append_list(dst, "exclude_recipe_patterns", patch.append_exclude_recipe_patterns)
  append_list(dst, "exclude_ingredient_patterns", patch.append_exclude_ingredient_patterns)
  append_groups(dst, patch.append_groups)

  for field, value in pairs(patch) do
    if not string.match(field, "^append_") then
      dst[field] = value
    end
  end
end

local function apply_profile(config, profile)
  if profile.streams then
    for key, patch in pairs(profile.streams) do
      config.streams[key] = config.streams[key] or {}
      patch_stream(config.streams[key], patch)
    end
  end
end

local PROFILES = {
  -- This table is intentionally small for now. It gives future compatibility
  -- work a stable place for mod-specific stream patches without bloating the
  -- base stream definitions.
}

function P.apply(config)
  for mod_name, profile in pairs(PROFILES) do
    if mods and mods[mod_name] then
      apply_profile(config, profile)
    end
  end
end

return P

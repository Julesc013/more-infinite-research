local P = {}

local function sorted_keys(tbl)
  local keys = {}
  for key, _ in pairs(tbl or {}) do
    table.insert(keys, key)
  end
  table.sort(keys)
  return keys
end

local function append_list(dst, field, values)
  if not values then return end

  dst[field] = dst[field] or {}
  local seen = {}
  for _, existing in ipairs(dst[field]) do
    seen[existing] = true
  end

  for _, value in ipairs(values) do
    if not seen[value] then
      seen[value] = true
      table.insert(dst[field], value)
    end
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

local function known_competing_productivity_profile(patterns)
  return {
    known_competing_productivity = {
      tech_patterns = patterns
    }
  }
end

local SCIENCE_PACK_PRODUCTIVITY_TECH_PATTERNS = {
  "^automation%-science%-productivity%-4$",
  "^logistic%-science%-productivity%-4$",
  "^military%-science%-productivity%-4$",
  "^chemical%-science%-productivity%-4$",
  "^production%-science%-productivity%-4$",
  "^utility%-science%-productivity%-4$",
  "^space%-science%-productivity%-4$",
  "^metallurgic%-science%-productivity%-4$",
  "^electromagnetic%-science%-productivity%-4$",
  "^agricultural%-science%-productivity%-4$",
  "^cryogenic%-science%-productivity%-4$",
  "^promethium%-science%-productivity%-4$"
}

local SEM_PRFE_PRODUCTIVITY_TECH_PATTERNS = {
  "^sem%-prfe_.+%-productivity%-1$"
}

local PROFILES = {
  -- This table is intentionally small for now. It gives future compatibility
  -- work a stable place for mod-specific stream patches without bloating the
  -- base stream definitions.
  --
  -- Profiles are applied from settings.lua as well as data stage. Keep profile
  -- patches declarative and do not inspect data.raw here. Prototype-dependent
  -- compatibility belongs in data-updates.lua or data-final-fixes.lua.
  ["bioflux-productivity"] = known_competing_productivity_profile({
    "^bioflux%-productivity$"
  }),

  ["crafting-efficiency-2"] = known_competing_productivity_profile({
    "^ce%-.+%-%d+$"
  }),

  ["ExpandedProductivityResearch"] = known_competing_productivity_profile({
    "^epr_.+%-productivity%-%d+$"
  }),

  ["fish-productivity"] = known_competing_productivity_profile({
    "^fish%-breeding%-productivity$"
  }),

  ["mir-fixture-plates-n-circuit-productivity"] = {
    known_competing_productivity = {
      tech_patterns = {
        "^basic%-plate%-productivity$",
        "^plate%-productivity$",
        "^electric%-circuit%-productivity$",
        "^electronic%-circuit%-productivity$",
        "^advanced%-circuit%-productivity$"
      }
    }
  },

  ["mir-fixture-plates-n-circuit-productivity-blocked"] = {
    known_competing_productivity = {
      tech_patterns = {
        "^basic%-plate%-productivity$",
        "^plate%-productivity$",
        "^electric%-circuit%-productivity$",
        "^electronic%-circuit%-productivity$",
        "^advanced%-circuit%-productivity$"
      }
    }
  },

  ["mir-fixture-plates-n-circuit-productivity-change-mismatch"] = {
    known_competing_productivity = {
      tech_patterns = {
        "^basic%-plate%-productivity$",
        "^plate%-productivity$",
        "^electric%-circuit%-productivity$",
        "^electronic%-circuit%-productivity$",
        "^advanced%-circuit%-productivity$"
      }
    }
  },

  ["ProductivityResearch"] = known_competing_productivity_profile(SEM_PRFE_PRODUCTIVITY_TECH_PATTERNS),

  ["ProductivityResearchForEveryone"] = known_competing_productivity_profile(SEM_PRFE_PRODUCTIVITY_TECH_PATTERNS),

  ["ProductivityResearchForEveryoneFG"] = known_competing_productivity_profile(SEM_PRFE_PRODUCTIVITY_TECH_PATTERNS),

  ["Science_packs_productivity"] = known_competing_productivity_profile(SCIENCE_PACK_PRODUCTIVITY_TECH_PATTERNS),

  ["plates-n-circuit-productivity"] = {
    known_competing_productivity = {
      tech_patterns = {
        "^basic%-plate%-productivity$",
        "^plate%-productivity$",
        "^electric%-circuit%-productivity$",
        "^electronic%-circuit%-productivity$",
        "^advanced%-circuit%-productivity$"
      }
    }
  }
}

function P.active_profiles()
  local active = {}
  for _, mod_name in ipairs(sorted_keys(PROFILES)) do
    if mods and mods[mod_name] then
      table.insert(active, {
        mod = mod_name,
        profile = PROFILES[mod_name]
      })
    end
  end
  return active
end

function P.active_known_competing_productivity_profiles()
  local active = {}
  for _, entry in ipairs(P.active_profiles()) do
    if entry.profile.known_competing_productivity then
      table.insert(active, {
        mod = entry.mod,
        policy = entry.profile.known_competing_productivity
      })
    end
  end
  return active
end

function P.known_competing_productivity_tech_name(name)
  for _, entry in ipairs(P.active_known_competing_productivity_profiles()) do
    for _, pattern in ipairs(entry.policy.tech_patterns or {}) do
      if string.find(name, pattern) then
        return true, entry.mod
      end
    end
  end
  return false, nil
end

function P.apply(config)
  for _, entry in ipairs(P.active_profiles()) do
    apply_profile(config, entry.profile)
  end
end

return P

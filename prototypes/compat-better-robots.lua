local cleanup = require("prototypes.lib.technology-cleanup")

local function has_prereq(tech, prereq_name)
  for _, name in ipairs((tech and tech.prerequisites) or {}) do
    if name == prereq_name then return true end
  end
  return false
end

local function has_worker_storage_effect(tech)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "worker-robot-storage" then return true end
  end
  return false
end

local function should_remove_worker_storage_extension(name, tech)
  if not tech or tech.max_level ~= "infinite" then return false end
  if not has_worker_storage_effect(tech) then return false end
  if not (has_prereq(tech, "worker-robots-storage-3") or has_prereq(tech, "worker-robots-storage-4")) then
    return false
  end
  -- Keep vanilla chain levels; only remove alternate infinite continuations.
  if name == "worker-robots-storage-1" or name == "worker-robots-storage-2" or name == "worker-robots-storage-3" then
    return false
  end
  return true
end

local function prefer_this_mod_for_competing_techs()
  local setting = settings and settings.startup and settings.startup["mir-prefer-this-mod-for-competing-techs"]
  if setting == nil then return true end
  return setting.value ~= false
end

if mods and mods["Better_Robots_Extended"] then
  if prefer_this_mod_for_competing_techs() then
    local to_remove = {}
    for name, tech in pairs(data.raw.technology or {}) do
      if should_remove_worker_storage_extension(name, tech) then
        table.insert(to_remove, name)
      end
    end
    for _, name in ipairs(to_remove) do
      cleanup.remove_technology_and_prereq_refs(name)
      log("[more-infinite-research] Removed competing worker robot storage infinite tech: " .. name)
    end
  end
end

local defaults = require("defaults")
local cleanup = require("prototypes.lib.technology-cleanup")
local settings_resolver = require("prototypes.settings-resolver")

local M = {}

local COMPETING_BASE_EXTENSIONS = {
  ["Better_Robots_Extended"] = {
    ["worker-robots-storage"] = {
      effect_type = "worker-robot-storage",
      prereq_candidates = {
        ["worker-robots-storage-3"] = true,
        ["worker-robots-storage-4"] = true
      },
      preserve_names = {
        ["worker-robots-storage-1"] = true,
        ["worker-robots-storage-2"] = true,
        ["worker-robots-storage-3"] = true
      }
    }
  }
}

local function startup_setting(name)
  local s = settings and settings.startup and settings.startup[name]
  if s then return s.value end
  return nil
end

local function prefer_this_mod_for_competing_techs()
  local value = startup_setting("mir-prefer-this-mod-for-competing-techs")
  if value == nil then return true end
  return value ~= false
end

local function base_extension_enabled(key)
  local spec = defaults.base_extensions and defaults.base_extensions[key] or {}
  return settings_resolver.base_enabled(key, spec)
end

local function has_prereq_candidate(tech, candidates)
  if not candidates then return true end
  for _, name in ipairs((tech and tech.prerequisites) or {}) do
    if candidates[name] then return true end
  end
  return false
end

local function has_effect_type(tech, effect_type)
  if not effect_type then return true end
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == effect_type then return true end
  end
  return false
end

local function should_remove_base_extension(name, tech, spec)
  if not tech or tech.max_level ~= "infinite" then return false end
  if spec.preserve_names and spec.preserve_names[name] then return false end
  if not has_effect_type(tech, spec.effect_type) then return false end
  if not has_prereq_candidate(tech, spec.prereq_candidates) then return false end
  return true
end

function M.apply()
  if not prefer_this_mod_for_competing_techs() then return end
  if not mods then return end

  local to_remove = {}
  for mod_name, extensions in pairs(COMPETING_BASE_EXTENSIONS) do
    if mods[mod_name] then
      for key, spec in pairs(extensions) do
        if base_extension_enabled(key) then
          for name, tech in pairs(data.raw.technology or {}) do
            if should_remove_base_extension(name, tech, spec) then
              table.insert(to_remove, {
                name = name,
                key = key,
                mod_name = mod_name
              })
            end
          end
        end
      end
    end
  end

  table.sort(to_remove, function(a, b) return a.name < b.name end)
  for _, entry in ipairs(to_remove) do
    cleanup.remove_technology_and_prereq_refs(entry.name)
    log("[more-infinite-research] Removed competing base extension technology from "
      .. entry.mod_name .. " for " .. entry.key .. ": " .. entry.name)
  end
end

return M

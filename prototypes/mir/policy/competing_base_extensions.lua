local defaults = require("prototypes.mir.settings.defaults")
local replacement = require("prototypes.mir.emit.technology_replacement")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local settings_resolver = require("prototypes.mir.settings.resolver")
local effective_settings = require("prototypes.mir.settings.effective")

local M = {}
local prepared_replacements = nil

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
  return effective_settings.get(name)
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

function M.prepare()
  prepared_replacements = {}
  if not prefer_this_mod_for_competing_techs() then return end
  if not mods then return end

  for mod_name, extensions in pairs(COMPETING_BASE_EXTENSIONS) do
    if mods[mod_name] then
      for key, spec in pairs(extensions) do
        if base_extension_enabled(key) then
          for name, tech in pairs(data_raw.prototypes("technology")) do
            if should_remove_base_extension(name, tech, spec) then
              table.insert(prepared_replacements, {
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

  table.sort(prepared_replacements, function(a, b) return a.name < b.name end)
  for _, entry in ipairs(prepared_replacements) do
    log("[more-infinite-research] Prepared competing base extension for transactional replacement from "
      .. entry.mod_name .. " for " .. entry.key .. ": " .. entry.name)
  end
end

function M.ignores_existing_owner(name)
  for _, entry in ipairs(prepared_replacements or {}) do
    if entry.name == name then return true end
  end
  return false
end

function M.apply()
  for _, entry in ipairs(prepared_replacements or {}) do
    local replacements = generated_registry.sorted_names({ kind = "base_extension", key = entry.key })
    local replacement_name = replacements[1]
    if replacement_name then
      local replaced, reason = replacement.replace_technology(entry.name, replacement_name)
      if replaced then
        log("[more-infinite-research] Replaced competing base extension technology from "
          .. entry.mod_name .. " for " .. entry.key .. ": " .. entry.name .. " -> " .. replacement_name)
      else
        log("[more-infinite-research] Retained competing base extension technology because replacement was unsafe: "
          .. entry.name .. " reason=" .. tostring(reason))
      end
    else
      log("[more-infinite-research] Retained competing base extension technology because MIR emitted no replacement: "
        .. entry.name)
    end
  end
end

return M

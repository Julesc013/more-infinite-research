local D = require("prototypes.mir.report.diagnostics_sink")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local factorio_mods = require("prototypes.mir.platform.factorio.mods")

local M = {}

local EXACT_REPAIRS = {
  cubium = {
    versions = { ["1.0.30"] = true },
    planet = "cubium"
  },
  corrundum = {
    versions = { ["1.0.47"] = true },
    planet = "corrundum"
  }
}

local function factorio_2_1_or_newer()
  local major, minor = string.match(tostring(factorio_mods.version("base") or ""), "^(%d+)%.(%d+)")
  major, minor = tonumber(major), tonumber(minor)
  return major and minor and (major > 2 or (major == 2 and minor >= 1))
end

local function apply_exact_repair(mod_name, spec)
  local version = factorio_mods.version(mod_name)
  if not version or not spec.versions[tostring(version)] then return 0 end

  local repaired = {}
  for name, sound in pairs(data_raw.prototypes("ambient-sound")) do
    if sound.planet == spec.planet and sound.planets == nil then
      sound.planets = {sound.planet}
      sound.planet = nil
      table.insert(repaired, name)
    end
  end
  if #repaired == 0 then return 0 end
  table.sort(repaired)

  local subjects = table.concat(repaired, ",")
  log("[more-infinite-research] Applied Factorio 2.1 ambient-sound schema repair for "
    .. mod_name .. " " .. tostring(version) .. ": " .. subjects)
  D.rule_mutation({
    key = "factorio_2_1_ambient_sound_schema",
    status = "repaired",
    reason = "exact_mod_version_schema_repair",
    mod = mod_name,
    ambient_sounds = subjects,
    field = "ambient-sound.planets",
    observed_value = tostring(version),
    expected_baseline = "Factorio 2.1 ambient-sound schema",
    likely_mutator_mod = mod_name,
    evidence = "exact-version-loader-schema-repair"
  })
  return #repaired
end

function M.apply()
  if not factorio_2_1_or_newer() then return 0 end
  local count = 0
  for mod_name, spec in pairs(EXACT_REPAIRS) do
    count = count + apply_exact_repair(mod_name, spec)
  end
  return count
end

return M

-- Private qualification observer.  It does not mutate gameplay or settings.
-- A fresh observer version is used only for paired 4.2.2/4.3.0 Full captures.
local OUTPUT_PREFIX = "mir430-full-technology-"

local function copy(value)
  if type(value) == "table" then
    local out = {}
    for key, item in pairs(value) do out[copy(key)] = copy(item) end
    return out
  end
  if value == nil or type(value) == "string" or type(value) == "number" or type(value) == "boolean" then return value end
  error("MIR430 capture encountered an unsupported value")
end

local function copy_effects(effects)
  local out = {}
  for index, effect in pairs(effects or {}) do
    local row = {}
    for key, value in pairs(effect) do row[key] = copy(value) end
    out[index] = row
  end
  return out
end

local function sorted_names(values)
  local out = {}
  for name in pairs(values or {}) do out[#out + 1] = name end
  table.sort(out)
  return out
end

local function snapshot_force(force)
  local technologies = {}
  for _, name in ipairs(sorted_names(force.technologies)) do
    local technology = force.technologies[name]
    local prerequisites, ingredients = {}, {}
    for prerequisite in pairs(technology.prerequisites or {}) do prerequisites[#prerequisites + 1] = prerequisite end
    table.sort(prerequisites)
    for _, ingredient in pairs(technology.research_unit_ingredients or {}) do
      ingredients[#ingredients + 1] = { name = ingredient.name, amount = ingredient.amount }
    end
    table.sort(ingredients, function(a, b)
      if a.name == b.name then return a.amount < b.amount end
      return a.name < b.name
    end)
    technologies[name] = {
      enabled = technology.enabled,
      visible_when_disabled = technology.visible_when_disabled,
      prototype = {
        order = technology.prototype.order,
        hidden = technology.prototype.hidden,
        max_level = technology.prototype.max_level,
        prerequisites = prerequisites,
        ingredients = ingredients,
        effects = copy_effects(technology.prototype.effects),
        unit_count = technology.research_unit_count,
        unit_count_formula = technology.research_unit_count_formula or "",
        unit_energy = technology.research_unit_energy
      }
    }
  end
  local startup = {}
  for name, value in pairs(settings.startup or {}) do startup[name] = copy(value.value) end
  return { technologies = technologies, settings = startup }
end

script.on_init(function()
  local version = script.active_mods["more-infinite-research"] or "absent"
  local stage = version == "4.2.20002" and "source" or "candidate"
  local active = {}
  for name, mod_version in pairs(script.active_mods or {}) do active[name] = mod_version end
  local forces = {}
  for name, force in pairs(game.forces) do forces[name] = snapshot_force(force) end
  local row = {
    schema = 1,
    kind = "MIR430FullTechnologySnapshotV1",
    stage = stage,
    package_version = version,
    active_mods = active,
    forces = forces
  }
  local name = OUTPUT_PREFIX .. stage .. ".json"
  helpers.write_file(name, helpers.table_to_json(row), false)
  log("[MIR430-CAPTURE] stage=" .. stage .. " package=" .. version .. " technologies=" .. #sorted_names(forces.player and forces.player.technologies or {}) .. " output=" .. name)
end)

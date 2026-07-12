local deepcopy = require("prototypes.mir.core.deepcopy")
local effect_metadata = require("prototypes.mir.domain.effects.metadata")

local M = {}

local settings_sort_names = {
  research_advanced_circuit = "Advanced circuit productivity",
  research_agricultural_growth_speed = "Agricultural growth speed",
  research_air_scrubbing_clean_filter = "Air Scrubbing clean-filter productivity",
  research_armor_components = "Armor component productivity",
  research_ash_separation = "Ash separation productivity",
  research_bacteria_cultivation = "Bacteria cultivation productivity",
  research_batteries = "Battery productivity",
  research_belts = "Transport belt productivity",
  research_bioflux = "Bioflux productivity",
  research_breeding = "Breeding productivity",
  research_bullets = "Bullet productivity",
  research_cannon_shooting_speed = "Cannon shooting speed",
  research_cargo_bay_unloading_distance = "Cargo bay unloading distance",
  research_cargo_landing_pad_count = "Cargo landing pad count",
  research_artificial_soil = "Artificial soil productivity",
  research_carbon = "Carbon productivity",
  research_carbon_fiber = "Carbon fiber productivity",
  research_character_crafting_speed = "Character crafting speed",
  research_character_mining_speed = "Character mining speed",
  research_character_reach = "Character reach bonus",
  research_character_walking_speed = "Character walking speed",
  research_concrete = "Concrete productivity",
  research_copper = "Copper plate productivity",
  research_copper_cable = "Copper cable productivity",
  research_electric_energy = "Electric energy productivity",
  research_electric_engine = "Electric engine unit productivity",
  research_electric_shooting_speed = "Electric shooting speed",
  research_electronic_circuit = "Electronic circuit productivity",
  research_engine = "Engine unit productivity",
  research_explosives = "Explosives productivity",
  research_flamethrower_shooting_speed = "Flamethrower shooting speed",
  research_flying_robot_frame = "Flying robot frame productivity",
  research_furnace = "Furnace productivity",
  research_gears = "Iron gear wheel productivity",
  research_grenades = "Grenade productivity",
  research_heavy_ammo = "Cannon shell productivity",
  research_holmium = "Holmium productivity",
  research_ice = "Ice productivity",
  research_inserters = "Inserter productivity",
  research_inventory_capacity = "Character inventory slots",
  research_iron = "Iron plate productivity",
  research_iron_sticks = "Iron stick productivity",
  research_lab_productivity = "Research productivity",
  research_landfill = "Landfill productivity",
  research_lithium = "Lithium productivity",
  research_low_density_structure = "Low density structure productivity",
  research_mining_drill = "Mining drill productivity",
  research_modules = "Module productivity",
  research_molten_metals = "Molten metals productivity",
  research_lubricant_productivity = "Lubricant productivity",
  research_oil_cracking_productivity = "Oil cracking productivity",
  research_oil_processing_productivity = "Oil processing productivity",
  research_plastic = "Plastic productivity",
  research_processing_unit = "Processing unit productivity",
  research_quantum_processor = "Quantum processor productivity",
  research_rails = "Rail productivity",
  research_robot_battery = "Worker robot battery",
  research_rocket_fuel = "Rocket fuel productivity",
  research_rocket_shooting_speed = "Rocket shooting speed",
  research_rockets = "Rocket productivity",
  research_science_pack_productivity = "Science pack productivity",
  research_spoilage_preservation = "Spoilage preservation",
  research_sulfur = "Sulfur productivity",
  research_sulfuric_acid_productivity = "Sulfuric acid productivity",
  research_supercapacitor = "Supercapacitor productivity",
  research_superconductor = "Superconductor productivity",
  research_thruster_fuel_productivity = "Thruster fuel productivity",
  research_thruster_oxidizer_productivity = "Thruster oxidizer productivity",
  research_tungsten = "Tungsten productivity",
  research_walls = "Wall productivity"
}

local function append_unique(out, seen, value)
  if value ~= nil and not seen[value] then
    seen[value] = true
    table.insert(out, value)
  end
end

local function sorted_unique(values)
  local out = {}
  local seen = {}
  for _, value in ipairs(values or {}) do append_unique(out, seen, value) end
  table.sort(out)
  return out
end

local function numeric_effect(effect)
  return effect_metadata.numeric_descriptor(effect)
end

local function close_to_integer(value)
  return math.abs(value - math.floor(value + 0.5)) < 0.000001
end

local function explicit_effect(spec)
  local source = spec and spec.effect_per_level
  if type(source) ~= "table" then return nil end
  local anchor = tonumber(source.canonical_anchor)
  if not anchor or anchor <= 0 then
    error("Explicit MIR effect contract requires a positive canonical_anchor.", 3)
  end
  local unit = source.unit == "native" and "native" or "percent"
  return {
    field = source.field or "modifier",
    unit = unit,
    display_multiplier = tonumber(source.display_multiplier) or (unit == "percent" and 100 or 1),
    canonical_anchor = anchor,
    whole_number = source.whole_number == true,
    runtime_multiplier_delta = source.runtime_multiplier_delta == true
  }
end

local function direct_effect_contract(key, spec)
  local explicit = explicit_effect(spec)
  if explicit then return explicit end

  local contract = nil
  for _, effect in ipairs(spec.direct_effects or {}) do
    local candidate = numeric_effect(effect)
    if candidate and candidate.value > 0 then
      if contract and (contract.field ~= candidate.field or contract.unit ~= candidate.unit) then
        error("MIR stream " .. key .. " mixes incompatible numeric effect contracts.", 3)
      end
      if not contract then
        contract = {
          field = candidate.field,
          unit = candidate.unit,
          display_multiplier = candidate.display_multiplier,
          canonical_anchor = candidate.value
        }
      elseif candidate.value > contract.canonical_anchor then
        contract.canonical_anchor = candidate.value
      end
    end
  end
  if not contract then
    error("MIR direct-effect stream " .. key .. " has no typed positive effect contract.", 3)
  end
  contract.whole_number = contract.unit == "native" and close_to_integer(contract.canonical_anchor)
  contract.runtime_multiplier_delta = false
  return contract
end

local function productivity_effect_contract(spec)
  local explicit = explicit_effect(spec)
  if explicit then return explicit end

  local anchor = nil
  for _, group in ipairs(spec.groups or {}) do
    local change = tonumber(group.change)
    if change and change > 0 and (not anchor or change > anchor) then anchor = change end
  end
  anchor = anchor or 0.10
  return {
    field = "change",
    unit = "percent",
    display_multiplier = 100,
    canonical_anchor = anchor,
    whole_number = false,
    runtime_multiplier_delta = false
  }
end

local function target_requirements(spec, kind, effect)
  local features = {}
  if kind == "recipe-productivity" then table.insert(features, "recipe_productivity") end
  if effect.runtime_multiplier_delta then table.insert(features, "scripted_techs") end
  for _, feature in ipairs(spec.requires_features or {}) do table.insert(features, feature) end

  local effect_types = {}
  for _, row in ipairs(spec.direct_effects or {}) do
    if row.type and row.type ~= "nothing" then table.insert(effect_types, row.type) end
  end

  return {
    requires_features = sorted_unique(features),
    required_mods = sorted_unique(spec.required_mods),
    required_items = sorted_unique(spec.required_items),
    required_fluids = sorted_unique(spec.required_fluids),
    required_technologies = sorted_unique(spec.required_technologies),
    required_effect_types = sorted_unique(effect_types)
  }
end

function M.normalize(key, raw_spec)
  if type(key) ~= "string" or key == "" then error("MIR stream descriptor requires a stable id.", 2) end
  if type(raw_spec) ~= "table" then error("MIR stream " .. key .. " must be a table.", 2) end
  if raw_spec.descriptor ~= nil then
    error("Raw MIR stream " .. key .. " must not inject a canonical descriptor through an overlay.", 2)
  end

  local spec = deepcopy(raw_spec)
  local kind = spec.direct_effects and "direct-effect" or "recipe-productivity"
  local effect = kind == "direct-effect"
    and direct_effect_contract(key, spec)
    or productivity_effect_contract(spec)
  spec.descriptor = {
    schema = 1,
    id = key,
    kind = kind,
    effect = effect,
    targets = target_requirements(spec, kind, effect),
    ui = {
      sort_name = settings_sort_names[key] or (key:gsub("^research_", ""):gsub("_", " "))
    }
  }
  return spec
end

function M.clone(spec)
  return deepcopy(spec)
end

return M

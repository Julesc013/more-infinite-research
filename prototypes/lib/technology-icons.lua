local deepcopy = require("prototypes.lib.deepcopy")
local lookup = require("prototypes.lib.prototype-lookup")

local I = {}

local CONSTANT_OVERLAYS = {
  ["recipe-productivity"] = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
  speed = "__core__/graphics/icons/technology/constants/constant-speed.png",
  ["movement-speed"] = "__core__/graphics/icons/technology/constants/constant-movement-speed.png",
  mining = "__core__/graphics/icons/technology/constants/constant-mining.png",
  capacity = "__core__/graphics/icons/technology/constants/constant-capacity.png",
  damage = "__core__/graphics/icons/technology/constants/constant-damage.png",
  range = "__core__/graphics/icons/technology/constants/constant-range.png",
  ["braking-force"] = "__core__/graphics/icons/technology/constants/constant-braking-force.png",
  equipment = "__core__/graphics/icons/technology/constants/constant-equipment.png",
  count = "__core__/graphics/icons/technology/constants/constant-count.png"
}

local function copy_icons(icons)
  local out = {}
  for _, layer in ipairs(icons or {}) do
    table.insert(out, deepcopy(layer))
  end
  return out
end

local function is_constant_overlay(layer)
  return layer
    and layer.icon
    and string.find(layer.icon, "__core__/graphics/icons/technology/constants/", 1, true) ~= nil
end

local function strip_constant_overlays(icons)
  local out = {}
  for _, layer in ipairs(icons or {}) do
    if not is_constant_overlay(layer) then
      table.insert(out, deepcopy(layer))
    end
  end
  return out
end

local function icons_from_tech(name)
  local t = (data.raw.technology or {})[name]
  if not t then return nil end
  if t.icons then return copy_icons(t.icons) end
  if t.icon then return {{icon = t.icon, icon_size = t.icon_size or 64}} end
  return nil
end

local function icon_from_item(name)
  local it = lookup.item_prototype(name)
  if not it then return nil end
  if it.icons then return copy_icons(it.icons) end
  if it.icon then return {{icon = it.icon, icon_size = it.icon_size or 64}} end
  return nil
end

local function required_mods_loaded(candidate)
  if not candidate then return true end

  if candidate.required_mod and not lookup.mod_exists(candidate.required_mod) then
    return false
  end

  if candidate.mod and not lookup.mod_exists(candidate.mod) then
    return false
  end

  for _, mod_name in ipairs(candidate.required_mods or {}) do
    if not lookup.mod_exists(mod_name) then return false end
  end

  return true
end

local function source_label(kind, name)
  if kind == "technology" then return "tech:" .. tostring(name) end
  if kind == "item" then return "item:" .. tostring(name) end
  if kind == "icon" then return tostring(name) end
  return tostring(kind or "fallback")
end

local function resolve_icon_candidate(candidate)
  if type(candidate) == "string" then
    local icons = icons_from_tech(candidate)
    if icons then return icons, source_label("technology", candidate) end

    icons = icon_from_item(candidate)
    if icons then return icons, source_label("item", candidate) end

    return nil, source_label("technology", candidate)
  end

  if type(candidate) ~= "table" or not required_mods_loaded(candidate) then
    return nil, nil
  end

  if candidate.icons then
    return copy_icons(candidate.icons), "custom-icons"
  end

  if candidate.icon then
    local entry = {icon = candidate.icon, icon_size = candidate.icon_size or 64}
    if candidate.icon_tint then entry.tint = candidate.icon_tint end
    return {entry}, source_label("icon", candidate.icon)
  end

  if candidate.technology then
    local icons = icons_from_tech(candidate.technology)
    if icons then return icons, source_label("technology", candidate.technology) end
  end

  if candidate.item then
    local icons = icon_from_item(candidate.item)
    if icons then return icons, source_label("item", candidate.item) end
  end

  return nil, nil
end

local function resolve_icon_candidates(candidates)
  local fallback_source = nil
  for _, candidate in ipairs(candidates or {}) do
    local icons, source = resolve_icon_candidate(candidate)
    fallback_source = fallback_source or source
    if icons then return icons, source end
  end
  return nil, fallback_source
end

local function append_legacy_candidates(out, stream)
  for _, name in ipairs(stream.icon_techs or {}) do
    table.insert(out, {technology = name})
    table.insert(out, {item = name})
  end

  if stream.icon_tech then
    table.insert(out, {technology = stream.icon_tech})
    table.insert(out, {item = stream.icon_tech})
  end

  if stream.icon_item then
    table.insert(out, {item = stream.icon_item})
  end

  if stream.items and stream.items[1] then
    table.insert(out, {item = stream.items[1]})
  end
end

local function resolve_base_icons_for_stream(stream)
  stream = stream or {}

  local base = nil
  if stream.icons then
    base = copy_icons(stream.icons)
    return base, "custom-icons"
  elseif stream.icon then
    local entry = {icon = stream.icon, icon_size = stream.icon_size or 64}
    if stream.icon_tint then entry.tint = stream.icon_tint end
    base = {entry}
    return base, source_label("icon", stream.icon)
  end

  local candidates = {}
  for _, candidate in ipairs(stream.icon_candidates or {}) do
    table.insert(candidates, candidate)
  end
  append_legacy_candidates(candidates, stream)

  local icons, source = resolve_icon_candidates(candidates)
  if icons then return copy_icons(icons), source end
  return nil, source or "fallback"
end

local function overlay_for_stream(stream)
  if stream.overlay ~= nil then return stream.overlay end

  local effect = stream.direct_effects and stream.direct_effects[1]
  if effect then
    local t = effect.type
    if t == "character-running-speed" then return "movement-speed" end
    if t == "character-mining-speed" then return "mining" end
    if t == "laboratory-productivity" then return "recipe-productivity" end
    if t == "character-reach-distance"
      or t == "character-build-distance"
      or t == "character-resource-reach-distance"
      or t == "character-item-drop-distance" then return "range" end
    if t == "character-inventory-slots-bonus"
      or t == "character-logistic-trash-slots"
      or t == "worker-robot-battery" then return "capacity" end
    if t == "max-cargo-bay-unloading-distance" then return "range" end
    if t == "cargo-landing-pad-count" then return "count" end
    if t == "gun-speed" or t == "character-crafting-speed" then return "speed" end
    if t == "braking-force" then return "braking-force" end
    if t == "ammo-damage" or t == "turret-attack" then return "damage" end
  end

  return "recipe-productivity"
end

local function add_constant_overlay(base_icons, overlay)
  local out = strip_constant_overlays(base_icons)
  if #out == 0 then
    out = {{
      icon = "__base__/graphics/technology/mining-productivity.png",
      icon_size = 256
    }}
  end
  if overlay == false then return out end

  local path = CONSTANT_OVERLAYS[overlay or "recipe-productivity"] or overlay
  if type(path) ~= "string" then return out end

  -- Match Wube's technology constant helpers so the corner badge floats
  -- outside normal icon bounds instead of shrinking the base icon.
  table.insert(out, {
    icon = path,
    icon_size = 128,
    scale = 0.5,
    shift = {50, 50},
    floating = true
  })
  return out
end

function I.icons_for_stream(stream)
  local base = resolve_base_icons_for_stream(stream)
  return add_constant_overlay(base, overlay_for_stream(stream))
end

function I.effect_icons_for_stream(stream)
  local base = resolve_base_icons_for_stream(stream)
  if base and #base > 0 then return base end
  return {{
    icon = "__base__/graphics/technology/mining-productivity.png",
    icon_size = 256
  }}
end

function I.icon_source_for_stream(stream)
  local _, source = resolve_base_icons_for_stream(stream)
  return source or "fallback"
end

return I

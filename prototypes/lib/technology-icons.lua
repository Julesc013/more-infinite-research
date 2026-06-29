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

local function has_constant_overlay(icons)
  for _, layer in ipairs(icons or {}) do
    if layer.icon and string.find(layer.icon, "__core__/graphics/icons/technology/constants/", 1, true) then
      return true
    end
  end
  return false
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

local function overlay_for_stream(stream)
  if stream.overlay ~= nil then return stream.overlay end

  local effect = stream.direct_effects and stream.direct_effects[1]
  if effect then
    local t = effect.type
    if t == "character-running-speed" then return "movement-speed" end
    if t == "character-mining-speed" then return "mining" end
    if t == "character-reach-distance"
      or t == "character-build-distance"
      or t == "character-resource-reach-distance"
      or t == "character-item-drop-distance" then return "range" end
    if t == "character-inventory-slots-bonus"
      or t == "character-logistic-trash-slots"
      or t == "worker-robot-battery" then return "capacity" end
    if t == "max-cargo-bay-unloading-distance" then return "range" end
    if t == "gun-speed" or t == "character-crafting-speed" then return "speed" end
    if t == "braking-force" then return "braking-force" end
    if t == "ammo-damage" or t == "turret-attack" then return "damage" end
  end

  return "recipe-productivity"
end

local function add_constant_overlay(base_icons, overlay)
  local out = copy_icons(base_icons)
  if #out == 0 then
    out = {{
      icon = "__base__/graphics/technology/mining-productivity.png",
      icon_size = 256
    }}
  end
  if overlay == false or has_constant_overlay(out) then return out end

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
  local base = nil
  if stream.icons then
    base = stream.icons
  elseif stream.icon then
    local entry = {icon = stream.icon, icon_size = stream.icon_size or 64}
    if stream.icon_tint then entry.tint = stream.icon_tint end
    base = {entry}
  elseif stream.icon_tech then
    base = icons_from_tech(stream.icon_tech) or icon_from_item(stream.icon_tech)
  end
  if not base then
    local src = stream.icon_item or ((stream.items or {})[1])
    base = icon_from_item(src)
  end
  return add_constant_overlay(base, overlay_for_stream(stream))
end

return I

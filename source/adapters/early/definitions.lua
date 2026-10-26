-- Fixed, finite museum definitions for the pre-0.13 targets.  These are the
-- complete default rows shipped by the corresponding MIR museum tags, not a
-- settings surface or a reconstruction of their old runtime implementation.
local M = {}

local science = {
  {"science-pack-1", 1},
  {"science-pack-2", 1},
  {"science-pack-3", 1},
  {"alien-science-pack", 1},
}

local f006 = {
  {key="inserter-capacity", levels=5, prerequisite="inserter-stack-size-bonus-4", icon="__base__/graphics/technology/inserter-stack-size-bonus.png", effect="inserter-stack-size-bonus", modifier=1, count=400, increment=200, time=45},
  {key="rocket-shooting-speed", levels=5, prerequisite="rocket-speed-5", icon="__base__/graphics/technology/rocket-speed.png", effect="gun-speed", ammo_category="rocket", modifier=.15, count=500, increment=250, time=60},
  {key="rocket-damage", levels=4, prerequisite="rocket-damage-5", icon="__base__/graphics/technology/rocket-damage.png", effect="ammo-damage", ammo_category="rocket", modifier=.2, count=500, increment=250, time=60},
}

local f007_to_f011 = {
  {key="inserter-capacity", levels=5, prerequisite="inserter-stack-size-bonus-4", icon="__base__/graphics/technology/inserter-stack-size-bonus.png", effect="inserter-stack-size-bonus", modifier=1, count=400, increment=200, time=45},
  {key="gun-turret-damage", levels=5, prerequisite="gun-turret-damage-6", icon="__base__/graphics/technology/gun-turret-damage.png", effect="turret-attack", turret_id="gun-turret", modifier=.2, count=500, increment=250, time=60},
  {key="bullet-shooting-speed", levels=5, prerequisite="bullet-speed-6", icon="__base__/graphics/technology/bullet-speed.png", effect="gun-speed", ammo_category="bullet", modifier=.15, count=500, increment=250, time=60},
  {key="bullet-damage", levels=5, prerequisite="bullet-damage-6", icon="__base__/graphics/technology/bullet-damage.png", effect="ammo-damage", ammo_category="bullet", modifier=.2, count=500, increment=250, time=60},
  {key="toolbelt", levels=2, prerequisite="toolbelt", icon="__base__/graphics/technology/toolbelt.png", effect="num-quick-bars", modifier=1, count=600, increment=300, time=45},
}

local f012 = {
  {key="inserter-capacity", levels=5, prerequisite="inserter-stack-size-bonus-4", icon="__base__/graphics/technology/inserter-stack-size-bonus.png", effect="inserter-stack-size-bonus", modifier=1, count=400, increment=200, time=45},
  {key="gun-turret-damage", levels=5, prerequisite="gun-turret-damage-6", icon="__base__/graphics/technology/gun-turret-damage.png", effect="turret-attack", turret_id="gun-turret", modifier=.2, count=500, increment=250, time=60},
  {key="bullet-shooting-speed", levels=5, prerequisite="bullet-speed-6", icon="__base__/graphics/technology/bullet-speed.png", effect="gun-speed", ammo_category="bullet", modifier=.15, count=500, increment=250, time=60},
  {key="bullet-damage", levels=5, prerequisite="bullet-damage-6", icon="__base__/graphics/technology/bullet-damage.png", effect="ammo-damage", ammo_category="bullet", modifier=.2, count=500, increment=250, time=60},
  {key="toolbelt", levels=3, prerequisite="toolbelt", icon="__base__/graphics/technology/toolbelt.png", effect="num-quick-bars", modifier=1, count=600, increment=300, time=45},
  {key="logistic-trash-slots", levels=3, prerequisite="character-logistic-trash-slots-2", icon="__base__/graphics/technology/character-logistic-trash-slots.png", effect="character-logistic-trash-slots", modifier=5, count=600, increment=300, time=45},
}

local families = {
  f006=f006, f007=f007_to_f011, f008=f007_to_f011, f009=f007_to_f011,
  f010=f007_to_f011, f011=f007_to_f011, f012=f012,
}

local function copy_science()
  local out = {}
  for index, ingredient in ipairs(science) do out[index] = {ingredient[1], ingredient[2]} end
  return out
end

local function required_target(target)
  if type(target) ~= "table" or type(target.id) ~= "string"
    or target.reduced ~= true or target.research_levels ~= false or target.recipe_productivity ~= false then
    error("MIR early adapter requires a reduced finite early target", 3)
  end
  local selected = families[target.id]
  if selected == nil then error("MIR early adapter has no definition for target " .. target.id, 3) end
  return selected
end

local function required_raw(raw, selected)
  if type(raw) ~= "table" or type(raw.technology) ~= "table" or type(raw.tool) ~= "table" then
    error("MIR early adapter requires data.raw technology and tool tables", 3)
  end
  for _, ingredient in ipairs(science) do
    if type(raw.tool[ingredient[1]]) ~= "table" then
      error("MIR early adapter requires science tool " .. ingredient[1], 3)
    end
  end
  for _, family in ipairs(selected) do
    if type(raw.technology[family.prerequisite]) ~= "table" then
      error("MIR early adapter requires technology " .. family.prerequisite, 3)
    end
  end
end

local function technology(family, level)
  local effect = {type=family.effect, modifier=family.modifier}
  if family.ammo_category then effect.ammo_category = family.ammo_category end
  if family.turret_id then effect.turret_id = family.turret_id end
  return {
    type="technology", name="mir-" .. family.key .. "-" .. level,
    icon=family.icon, prerequisites={level == 1 and family.prerequisite or "mir-" .. family.key .. "-" .. (level - 1)},
    effects={effect}, unit={count=family.count + family.increment * (level - 1), ingredients=copy_science(), time=family.time},
    upgrade=true, order="z[mir]-" .. family.key .. "-" .. string.format("%02d", level),
  }
end

function M.technologies(target, raw)
  local selected = required_target(target)
  required_raw(raw, selected)
  local out = {}
  for _, family in ipairs(selected) do
    for level = 1, family.levels do out[#out + 1] = technology(family, level) end
  end
  return out
end

return M

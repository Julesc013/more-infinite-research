local function startup_setting(name)
  local s = settings and settings.startup and settings.startup[name]
  if s then return s.value end
  return nil
end

local function strip_categories_for_mode()
  local mode = startup_setting("mir-adjust-vanilla-weapon-speed-techs") or "off"
  if mode == "off" then return {} end

  if mode == "always" then
    return {
      rocket = true,
      ["cannon-shell"] = true
    }
  end

  local out = {}
  local tech_names = {
    "recipe-prod-research_rocket_shooting_speed-1",
    "recipe-prod-research_cannon_shooting_speed-1"
  }
  for _, tech_name in ipairs(tech_names) do
    local tech = (data.raw.technology or {})[tech_name]
    for _, effect in ipairs((tech and tech.effects) or {}) do
      if effect.type == "gun-speed" and effect.ammo_category then
        out[effect.ammo_category] = true
      end
    end
  end
  return out
end

local function strip_weapon_speed_effects()
  local strip_categories = strip_categories_for_mode()
  local techs = data.raw.technology or {}
  for name, tech in pairs(techs) do
    if string.match(name, "^weapon%-shooting%-speed%-%d+$") and tech.effects then
      local filtered = {}
      for _, effect in ipairs(tech.effects) do
        if effect.type == "gun-speed" then
          local category = effect.ammo_category
          if strip_categories[category] then
            -- Skip only categories this mod has explicitly taken over.
          else
            table.insert(filtered, effect)
          end
        else
          table.insert(filtered, effect)
        end
      end
      tech.effects = filtered
    end
  end
end

strip_weapon_speed_effects()

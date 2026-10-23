-- Exact F200 Krastorio 2 Base continuation effects. Science, prerequisites,
-- costs, inherited times, and identities remain the F200 Base declarations.
local function direct_effect(scale, ammo_category)
  return {type = "gun-speed", scale = scale, raw = false, ammo_category = ammo_category}
end

return {
  -- Exact F200 K2 Base presentation substitutions.  These preserve the
  -- authored Base family fields and use no K2SO selection body.
  definition_overrides = {
    research_belts = {icon = "__Krastorio2Assets__/technologies/logistics-1.png", icon_size = 256},
    research_copper = {icon = "__Krastorio2Assets__/icons/items/copper-plate.png", icon_size = 64},
    research_iron = {icon = "__Krastorio2Assets__/icons/items/iron-plate.png", icon_size = 64},
    research_mining_drill = {icon = "__Krastorio2Assets__/icons/entities/electric-mining-drill.png", icon_size = 64},
    research_steel = {icon = "__Krastorio2Assets__/technologies/steel-processing.png", icon_size = 256},
    research_science_pack_productivity = {icon = "__Krastorio2Assets__/technologies/optimization-tech-card.png", icon_size = 256},
    research_character_mining_speed = {icon = "__Krastorio2Assets__/technologies/steel-pickaxe.png", icon_size = 256},
    research_character_reach = {icon = "__Krastorio2Assets__/technologies/steel-pickaxe.png", icon_size = 256},
    research_lab_productivity = {icon = "__Krastorio2Assets__/technologies/military-tech-card.png", icon_size = 256},
  },
  continuation_overrides = {
    laser_shooting_speed = {
      effects = {direct_effect(0.2, "laser"), direct_effect(0.2, "kr-impulse-rifle")},
    },
    weapon_shooting_speed = {
      -- Cannon and rocket retain their dedicated authored F200 families;
      -- artillery remains in the existing heavy-ammo product family.
      effects = {
        direct_effect(0.375, "bullet"), direct_effect(0.375, "shotgun-shell"),
        direct_effect(0.375, "kr-pistol"), direct_effect(0.375, "kr-anti-materiel-rifle-ammo"),
        direct_effect(0.5, "kr-railgun-shell"), direct_effect(0.5, "kr-turret-missile"),
        direct_effect(0.5, "kr-heavy-rocket"),
      },
    },
  },
}

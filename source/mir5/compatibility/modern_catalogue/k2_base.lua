-- Exact F200 Krastorio 2 Base continuation effects. Science, prerequisites,
-- costs, inherited times, and identities remain the F200 Base declarations.
local function direct_effect(scale, ammo_category)
  return {type = "gun-speed", scale = scale, raw = false, ammo_category = ammo_category}
end

return {
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

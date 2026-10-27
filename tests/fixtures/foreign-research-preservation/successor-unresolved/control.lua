-- Read-only fresh-world witness. No state seeding, science production, lab
-- completion, migration or exact reporter reproduction is claimed.
local PACK = "mir5-foreign-astral-insight-pack"
local GEAR = "recipe-prod-research_gears-1"
local function fail(message) error("[mir5-foreign-unresolved] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= .0000001
end
local function observe()
  local active = script.active_mods
  if active.base ~= "2.1.23" or active["more-infinite-research"] ~= "5.0.21000"
      or active["mir-fixture-mir5-foreign-research-preservation"] ~= "0.3.0" then
    fail("fixture closure differs")
  end
  local force = game.forces.player
  if force == nil or force.valid == false then fail("player force is absent") end
  if force.recipes[PACK] ~= nil then fail("named foreign pack producer appeared") end
  for _, level in ipairs({61, 62}) do
    local name = "Space-Lab-Research-" .. level
    local row = force.technologies[name]
    local prototype = row and row.prototype
    local effects = prototype and prototype.effects
    local effect = effects and effects[1]
    if row == nil or row.valid == false or row.name ~= name or row.level ~= level
        or row.researched ~= false or row.enabled ~= true
        or prototype == nil or prototype.max_level ~= level
        or type(effects) ~= "table" or #effects ~= 1
        or effect.type ~= "laboratory-speed" or not close(effect.modifier, level / 1000) then
      fail("foreign native research changed: " .. name)
    end
  end
  local gear = force.technologies[GEAR]
  local recipe = force.recipes["iron-gear-wheel"]
  if gear == nil or gear.valid == false or gear.researched ~= false or gear.level ~= 1
      or recipe == nil or not close(recipe.productivity_bonus, 0)
      or not close(force.laboratory_speed_modifier, 0) then
    fail("ordinary MIR research or fresh native bonuses differ")
  end
  log("[MIR5_FOREIGN_UNRESOLVED] RESULT " .. helpers.table_to_json({
    case="SCI-RESEARCH-01-unresolved", stage="init", status="passed",
    qualification="representative-unresolved-source-startup-only",
    foreign_name="Space-Lab-Research-61", foreign_level=61,
    foreign_researched=false, pending_name="Space-Lab-Research-62",
    foreign_pack=PACK, named_pack_recipe_absent=true,
    mir_name=GEAR, mir_level=gear.level,
    laboratory_speed_modifier=force.laboratory_speed_modifier,
    gear_productivity_bonus=recipe.productivity_bonus,
  }))
end
script.on_init(observe)

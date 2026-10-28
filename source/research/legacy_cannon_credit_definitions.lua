-- Fixed hidden holder for the earned cannon component of MIR 1.2's combined
-- rocket-shooting-speed stream.  The modern public rocket stream intentionally
-- owns only rocket ammunition; this row carries no new public progression.
local M = {}

local ID = "mir-legacy-cannon-credit-rocket-shooting-speed"
local MAIN_ID = "recipe-prod-research_rocket_shooting_speed-1"
local ICON = "__base__/graphics/technology/automation-1.png"
local function finite_nonnegative(value)
  return type(value) == "number" and value == value and value >= 0
    and value < math.huge
end

local function copy_descriptor()
  return {
    id = ID,
    main_id = MAIN_ID,
    source_category = "rocket",
    credit_category = "cannon-shell",
  }
end

-- Runtime receives detached metadata and cannot alter this data-stage
-- identity.  The scalar deliberately remains a runtime observation of the
-- paired public rocket row, because the holder follows that stream's setting.
function M.descriptor()
  return copy_descriptor()
end

local function rocket_scalar(technology)
  if type(technology) ~= "table" or technology.name ~= MAIN_ID
      or type(technology.effects) ~= "table" or #technology.effects ~= 1 then
    return nil
  end
  local effect = technology.effects[1]
  if type(effect) ~= "table" or effect.type ~= "gun-speed"
      or effect.ammo_category ~= "rocket" or not finite_nonnegative(effect.modifier) then
    return nil
  end
  return effect.modifier
end

local function named_current_rows(technologies)
  if type(technologies) ~= "table" then
    error("MIR legacy cannon credit definitions require an output technology array", 3)
  end
  local found = {}
  for index = 1, #technologies do
    local technology = technologies[index]
    local name = type(technology) == "table" and technology.name or nil
    if name == MAIN_ID or name == ID then
      if found[name] ~= nil then error("MIR legacy cannon credit duplicate technology " .. name, 3) end
      found[name] = technology
    end
  end
  return found
end

local function holder(change)
  return {
    type = "technology",
    name = ID,
    icon = ICON,
    icon_size = 256,
    level = 1,
    upgrade = true,
    hidden = true,
    enabled = false,
    visible_when_disabled = false,
    max_level = "infinite",
    order = "zz[mir-legacy-cannon-credit]-rocket-shooting-speed",
    effects = {{type = "gun-speed", ammo_category = "cannon-shell", modifier = change}},
    unit = {count = 1, time = 1, ingredients = {{"automation-science-pack", 1}}},
  }
end

-- Appends the one detached holder only when the matching current public
-- rocket stream is already part of this explicit output batch.  It indexes
-- no foreign prototype collection and leaves the public row untouched.
function M.append(technologies, target)
  if type(target) ~= "table" or target.recipe_productivity ~= true then return {} end
  local rows = named_current_rows(technologies)
  if rows[MAIN_ID] == nil then return {} end
  if rows[ID] ~= nil then error("MIR legacy cannon credit identity is already owned", 2) end
  local change = rocket_scalar(rows[MAIN_ID])
  -- Generator retains malformed owned rows for its own complete local
  -- preflight.  Do not turn this detached migration holder into an earlier
  -- data-stage error or manufacture a replacement scalar from a default.
  if change == nil then return {} end
  local staged = {holder(change)}
  for index = 1, #staged do technologies[#technologies + 1] = staged[index] end
  return staged
end

return M

-- Detached native holders for the authored electric/tesla public stream.
-- Runtime owns paid-level accounting; the Generator owns publication.
local M = {}

local MAIN_ID = "recipe-prod-research_electric_shooting_speed-1"
local CATEGORIES = {"electric", "tesla"}
M.main_id = MAIN_ID

local function descriptor(category)
  return {
    main_id = MAIN_ID,
    category = category,
    positive_id = "mir-native-credit-research_electric_shooting_speed-" .. category .. "-positive",
    negative_id = "zz-mir-native-credit-research_electric_shooting_speed-" .. category .. "-negative",
  }
end

function M.descriptors()
  return {descriptor("electric"), descriptor("tesla")}
end

function M.private_ids()
  local out = {}
  for _, category in ipairs(CATEGORIES) do
    local row = descriptor(category)
    out[row.positive_id], out[row.negative_id] = true, true
  end
  return out
end

local function refuse(message)
  error("MIR native gun credit " .. message, 3)
end

local function plain(value)
  if type(value) ~= "table" or getmetatable(value) ~= nil then
    refuse("requires plain native tables")
  end
end

local function dense_length(value, maximum)
  plain(value)
  local count, last = 0, 0
  for index in pairs(value) do
    if type(index) ~= "number" or index < 1 or index >= math.huge
        or index ~= math.floor(index) or (maximum and index > maximum) then
      refuse("requires a bounded dense array")
    end
    count, last = count + 1, math.max(last, index)
  end
  if count ~= last then refuse("requires a dense array") end
  return count
end

local function finite_nonnegative(value)
  return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function effects(row)
  plain(row)
  if row.type ~= "technology" or row.name ~= MAIN_ID then
    refuse("requires the exact authored public technology")
  end
  local count = dense_length(row.effects, 2)
  local out = {}
  for index = 1, count do
    local effect = row.effects[index]
    plain(effect)
    for key in pairs(effect) do
      if key ~= "type" and key ~= "ammo_category" and key ~= "modifier" then
        refuse("effect has an unknown field")
      end
    end
    local category = effect.ammo_category
    if effect.type ~= "gun-speed" or (category ~= "electric" and category ~= "tesla")
        or not finite_nonnegative(effect.modifier) or out[category] ~= nil then
      refuse("effect is invalid or duplicated")
    end
    out[category] = effect.modifier
  end
  return out, count
end

local function ingredient_name(row)
  plain(row.unit)
  if dense_length(row.unit.ingredients) == 0 then refuse("requires authored science") end
  local first = row.unit.ingredients[1]
  if dense_length(first, 2) ~= 2 or type(first[1]) ~= "string" or first[1] == ""
      or first[1]:find("\0", 1, true) or not finite_nonnegative(first[2]) or first[2] == 0 then
    refuse("requires a valid first authored science ingredient")
  end
  return first[1]
end

local function holder(name, category, modifier, science, direction)
  return {
    type = "technology",
    name = name,
    icon = "__base__/graphics/technology/automation-1.png",
    icon_size = 256,
    hidden = true,
    enabled = false,
    visible_when_disabled = false,
    ignore_tech_cost_multiplier = true,
    upgrade = true,
    level = 1,
    max_level = "infinite",
    order = (direction == "positive" and "zz" or "zzz")
      .. "[mir-native-gun-credit]-" .. category .. "-" .. direction,
    effects = {{type = "gun-speed", ammo_category = category, modifier = modifier}},
    unit = {count_formula = "1", time = 1, ingredients = {{science, 1}}},
  }
end

function M.technologies(full_row, selected_row)
  if full_row == nil then return {} end
  local full, count = effects(full_row)
  -- Base has only electric. It has no partial two-category ownership to carry.
  if count == 1 and full.electric ~= nil then return {} end
  if count ~= 2 or full.electric == nil or full.tesla == nil then
    refuse("requires the authored electric/tesla effect pair")
  end
  local selected = effects(selected_row)
  for category, modifier in pairs(selected) do
    if modifier ~= full[category] then refuse("selected effect differs from the authored scalar") end
  end
  local science, out = ingredient_name(full_row), {}
  for _, category in ipairs(CATEGORIES) do
    local row, modifier = descriptor(category), full[category]
    out[#out + 1] = holder(row.positive_id, category, modifier, science, "positive")
    -- Inactive negative effects must be zero before runtime rebalances saved
    -- holder levels after a profile/category removal.
    out[#out + 1] = holder(row.negative_id, category,
      selected[category] ~= nil and -modifier or 0, science, "negative")
  end
  return out
end

return M

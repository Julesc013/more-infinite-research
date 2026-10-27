-- Fixed hidden holders for the one proven MIR 1.1 module-effect loss.
--
-- Published MIR 1.1 emitted both .10 and .01 productivity effects for each
-- tier-one module recipe. MIR5's public research_modules row deliberately
-- retains the normal .10 stream only. These holders retain the earned .01
-- contribution without changing that public row or joining the signed
-- competing-provider credit ledger.
local M = {}

local ICON = "__base__/graphics/technology/module.png"
local ORDER_PREFIX = "zz[mir-legacy-module-credit]-"
local MAIN_ID = "recipe-prod-research_modules-1"
local CHANGE = .01

local DESCRIPTORS = {
  {id = "mir-legacy-module-credit-speed-module", recipe = "speed-module"},
  {id = "mir-legacy-module-credit-productivity-module", recipe = "productivity-module"},
  {id = "mir-legacy-module-credit-efficiency-module", recipe = "efficiency-module"},
}

local function copy_descriptor(value)
  return {id = value.id, recipe = value.recipe, main_id = MAIN_ID, change = CHANGE}
end

-- Runtime receives detached metadata so it cannot mutate the authored rows.
function M.descriptors()
  local out = {}
  for index = 1, #DESCRIPTORS do out[index] = copy_descriptor(DESCRIPTORS[index]) end
  return out
end

local function row(descriptor)
  return {
    type = "technology",
    name = descriptor.id,
    icon = ICON,
    icon_size = 256,
    level = 1,
    upgrade = true,
    hidden = true,
    enabled = false,
    visible_when_disabled = false,
    max_level = "infinite",
    order = ORDER_PREFIX .. descriptor.id,
    effects = {{type = "change-recipe-productivity", recipe = descriptor.recipe, change = CHANGE}},
    unit = {count = 1, time = 1, ingredients = {{"automation-science-pack", 1}}},
  }
end

-- Data-stage callers append only these new detached tables. They never patch
-- the public module definition or inspect foreign prototypes.
function M.technologies()
  local out = {}
  for index = 1, #DESCRIPTORS do out[index] = row(DESCRIPTORS[index]) end
  return out
end

return M

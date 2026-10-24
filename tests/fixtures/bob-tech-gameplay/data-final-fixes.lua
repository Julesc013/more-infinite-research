-- Private BobTech plus Angel Smelting data preflight. The independently
-- recovered F210 facts are spelled out here. Every named item, route, owner,
-- and generated MIR stage is checked before the fixture changes a unit count
-- or research time. It uses direct names only; it does not discover recipes,
-- traverse technologies, or change settings.
local FAMILIES = {
  {
    key="research_material_tin", item="bob-tin-plate",
    icon="__angelssmeltinggraphics__/graphics/icons/plate-tin.png", icon_size=32,
    routes={
      {recipe="angels-plate-tin", owner="angels-tin-smelting-1", maximum_productivity=3,
       ingredients={{type="fluid",name="angels-liquid-molten-tin",amount=40}},
       results={{type="item",name="bob-tin-plate",amount=4}},
       owner_prerequisites={"angels-metallurgy-1"},
       owner_science={{type="item",name="automation-science-pack",amount=1}}},
      {recipe="angels-plate-tin-2", owner="angels-tin-casting-2", maximum_productivity=3,
       ingredients={{type="item",name="angels-roll-tin",amount=1}},
       results={{type="item",name="bob-tin-plate",amount=4}},
       owner_prerequisites={"angels-strand-casting-1","angels-tin-smelting-1","angels-copper-casting-2"},
       owner_science={{type="item",name="automation-science-pack",amount=1},{type="item",name="logistic-science-pack",amount=1}}},
    },
    early={id="recipe-prod-research_material_tin-1", level=1, max_level=3,
      order="p[research_material_tin]", count_formula="200*2^(L-1)", time=30,
      science={"automation-science-pack"},
      prerequisites={"automation-science-pack","angels-tin-smelting-1","angels-tin-casting-2"}},
    withheld="recipe-prod-research_material_tin-4",
  },
  {
    key="research_material_gunmetal", item="bob-gunmetal-alloy",
    icon="__angelssmeltinggraphics__/graphics/icons/plate-gunmetal.png", icon_size=32,
    routes={
      {recipe="angels-plate-gunmetal", owner="angels-gunmetal-smelting-1", maximum_productivity=3,
       ingredients={{type="fluid",name="angels-liquid-molten-gunmetal",amount=40}},
       results={{type="item",name="bob-gunmetal-alloy",amount=4}},
       owner_prerequisites={"angels-tin-smelting-1","angels-zinc-smelting-1","angels-copper-smelting-1"},
       owner_science={{type="item",name="automation-science-pack",amount=1},{type="item",name="logistic-science-pack",amount=1}}},
    },
    early={id="recipe-prod-research_material_gunmetal-1", level=1, max_level=3,
      order="p[research_material_gunmetal]", count_formula="200*2^(L-1)", time=30,
      science={"automation-science-pack","logistic-science-pack"},
      prerequisites={"angels-gunmetal-smelting-1","automation-science-pack","logistic-science-pack"}},
    continuation={id="recipe-prod-research_material_gunmetal-4", level=4, max_level="infinite",
      order="p[research_material_gunmetal__continuation]", count_formula="1600+200*(L-4)", time=30,
      science={"automation-science-pack","logistic-science-pack","space-science-pack"},
      prerequisites={"angels-gunmetal-smelting-1","automation-science-pack","logistic-science-pack","space-science-pack","recipe-prod-research_material_gunmetal-1"}},
  },
  {
    key="research_material_invar", item="bob-invar-alloy",
    icon="__angelssmeltinggraphics__/graphics/icons/plate-invar.png", icon_size=32,
    routes={
      {recipe="angels-plate-invar", owner="angels-invar-smelting-1", maximum_productivity=3,
       ingredients={{type="fluid",name="angels-liquid-molten-invar",amount=40}},
       results={{type="item",name="bob-invar-alloy",amount=4}},
       owner_prerequisites={"angels-steel-smelting-1","angels-nickel-smelting-1"},
       owner_science={{type="item",name="automation-science-pack",amount=1},{type="item",name="logistic-science-pack",amount=1}}},
    },
    early={id="recipe-prod-research_material_invar-1", level=1, max_level=3,
      order="p[research_material_invar]", count_formula="200*2^(L-1)", time=30,
      science={"automation-science-pack","logistic-science-pack"},
      prerequisites={"angels-invar-smelting-1","automation-science-pack","logistic-science-pack"}},
    continuation={id="recipe-prod-research_material_invar-4", level=4, max_level="infinite",
      order="p[research_material_invar__continuation]", count_formula="1600+200*(L-4)", time=30,
      science={"automation-science-pack","logistic-science-pack","space-science-pack"},
      prerequisites={"angels-invar-smelting-1","automation-science-pack","logistic-science-pack","space-science-pack","recipe-prod-research_material_invar-1"}},
  },
}

local function fail(message) error("[mir5-bob-tech-gameplay] " .. message) end
local function entry_name(value) return type(value) == "table" and (value.name or value[1]) or nil end
local function entry_amount(value) return type(value) == "table" and (value.amount or value[2]) or nil end

local function exact_names(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " count changed") end
  for index, value in ipairs(expected) do
    if actual[index] ~= value then fail(label .. " changed at " .. tostring(index)) end
  end
end

local function ordinary_rows(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " count changed") end
  for index, wanted in ipairs(expected) do
    local actual_row = actual[index]
    if type(actual_row) ~= "table" or (actual_row.type or "item") ~= wanted.type
        or entry_name(actual_row) ~= wanted.name or entry_amount(actual_row) ~= wanted.amount
        or actual_row.amount_min ~= nil or actual_row.amount_max ~= nil
        or (actual_row.probability ~= nil and actual_row.probability ~= 1)
        or (actual_row.independent_probability ~= nil and actual_row.independent_probability ~= 1)
        or (actual_row.catalyst_amount ~= nil and actual_row.catalyst_amount ~= 0)
        or (actual_row.ignored_by_productivity ~= nil and actual_row.ignored_by_productivity ~= 0) then
      fail(label .. " changed at " .. tostring(index))
    end
  end
end

local function owner_matches(owner, route)
  if type(owner) ~= "table" or owner.enabled == false then fail(route.owner .. " is unavailable") end
  exact_names(owner.prerequisites or {}, route.owner_prerequisites, route.owner .. " prerequisites")
  ordinary_rows(type(owner.unit) == "table" and owner.unit.ingredients or nil, route.owner_science, route.owner .. " science")
  local found = 0
  for _, effect in ipairs(owner.effects or {}) do
    if effect.recipe == route.recipe then
      if effect.type ~= "unlock-recipe" then fail(route.owner .. " ownership effect changed") end
      found = found + 1
    end
  end
  if found ~= 1 then fail(route.owner .. " no longer owns " .. route.recipe) end
end

local function assert_route(raw, route)
  local value = raw.recipe[route.recipe]
  local maximum = type(value) == "table" and value.maximum_productivity
  -- Independent F210 schema fact: this optional raw field defaults to 3.0.
  if maximum == nil then maximum = 3 end
  if type(value) ~= "table" or value.enabled ~= false or value.hidden == true
      or value.allow_productivity ~= true or maximum ~= route.maximum_productivity then
    fail(route.recipe .. " route flags changed")
  end
  ordinary_rows(value.ingredients, route.ingredients, route.recipe .. " ingredients")
  ordinary_rows(value.results, route.results, route.recipe .. " results")
  owner_matches(raw.technology[route.owner], route)
end

local function assert_stage(raw, family, stage, continuation)
  local value = raw.technology[stage.id]
  if type(value) ~= "table" or value.type ~= "technology" or value.name ~= stage.id
      or value.level ~= stage.level or value.upgrade ~= true or value.max_level ~= stage.max_level
      or value.order ~= stage.order or value.enabled == false then
    fail(stage.id .. " identity or progression changed")
  end
  if continuation then
    if value.show_levels_info ~= false or value.visible_when_disabled ~= true then
      fail(stage.id .. " continuation presentation changed")
    end
  elseif value.show_levels_info ~= nil or value.visible_when_disabled ~= nil then
    fail(stage.id .. " finite presentation changed")
  end
  exact_names(value.prerequisites or {}, stage.prerequisites, stage.id .. " prerequisites")
  for _, prerequisite in ipairs(stage.prerequisites) do
    if prerequisite ~= family.early.id and raw.technology[prerequisite] == nil then
      fail(stage.id .. " prerequisite is absent: " .. prerequisite)
    end
  end
  local unit = value.unit
  if type(unit) ~= "table" or unit.count ~= nil or unit.count_formula ~= stage.count_formula or unit.time ~= stage.time then
    fail(stage.id .. " ordinary cost or time changed")
  end
  local wanted_science = {}
  for _, name in ipairs(stage.science) do wanted_science[#wanted_science + 1] = {type="item",name=name,amount=1} end
  ordinary_rows(unit.ingredients, wanted_science, stage.id .. " science")
  if type(value.effects) ~= "table" or #value.effects ~= #family.routes then fail(stage.id .. " effect count changed") end
  for index, route in ipairs(family.routes) do
    local effect = value.effects[index]
    if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity"
        or effect.recipe ~= route.recipe or effect.change ~= .02 then
      fail(stage.id .. " recipe effect changed at " .. tostring(index))
    end
  end
  return value
end

local function assert_raw(raw, family)
  local item = raw.item[family.item]
  if type(item) ~= "table" or item.icon ~= family.icon or item.icon_size ~= family.icon_size then
    fail(family.item .. " presentation changed")
  end
  for _, route in ipairs(family.routes) do assert_route(raw, route) end
end

local raw = data.raw
if type(raw) ~= "table" or type(raw.item) ~= "table" or type(raw.recipe) ~= "table" or type(raw.technology) ~= "table" then
  fail("named BobTech plus Angel raw prototypes are unavailable")
end
local rows = {}
for _, family in ipairs(FAMILIES) do assert_raw(raw, family) end
for _, family in ipairs(FAMILIES) do
  rows[#rows + 1] = assert_stage(raw, family, family.early, false)
  if family.continuation then rows[#rows + 1] = assert_stage(raw, family, family.continuation, true) end
  if raw.technology[family.withheld or ""] ~= nil then fail((family.withheld or "") .. " must remain withheld") end
end
for _, value in ipairs(rows) do
  value.unit.count_formula, value.unit.count, value.unit.time = nil, 1, 1
end

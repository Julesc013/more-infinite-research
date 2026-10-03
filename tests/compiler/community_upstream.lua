-- Execute exact selected upstream files with a controlled data-stage boundary.
-- The immutable archives and versions are supplied by the host test input.
local records = dofile(assert(arg[2], "Pass the recorded upstream input file"))
local checks = 0
local function check(value, message)
  assert(value, message); checks=checks+1; print("OBSERVED\t" .. message)
end
local function unlocks(technology, recipe)
  for _, effect in ipairs((technology or {}).effects or {}) do
    if effect.type == "unlock-recipe" and effect.recipe == recipe then return true end
  end
  return false
end
local sources = {}
for _, record in ipairs(records) do
  sources[record.target] = sources[record.target] or {}
  sources[record.target][record.mod] = record
end
for _, target in ipairs({"f210","f200"}) do
  local selected = sources[target]
  for _, combination in ipairs({{matrix=true}, {accumulator=true}, {matrix=true,accumulator=true}, {matrix=true,accumulator=true,paracelsin=true}}) do
    mods = {base=target == "f210" and "2.1.20" or "2.0.76"}
    if combination.matrix then mods.SolarMatrix=selected.SolarMatrix.version end
    if combination.accumulator then mods["Accumulator-V2"]=selected["Accumulator-V2"].version end
    if combination.paracelsin then mods.Paracelsin="controlled-present" end
    settings = {startup={
      ["solar-matrix-power"]={value=128}, ["accumulator-power-capacity"]={value=10},
      ["link-multiplier-to-cost"]={value=false}
    }}
    data = {raw={recipe={},technology={}}}
    function data:extend(rows)
      for _, row in ipairs(rows) do self.raw[row.type]=self.raw[row.type] or {};self.raw[row.type][row.name]=row end
    end
    for _, name in ipairs({"Accumulator-V2","SolarMatrix"}) do
      if mods[name] then
        for _, file in ipairs({"prototypes/recipe.lua","prototypes/technology.lua"}) do
          assert(load(selected[name].files[file], "@" .. selected[name].path .. "/" .. file, "t", _G))()
        end
      end
    end
    if combination.matrix then
      check(unlocks(data.raw.technology["solar-matrix"],"solar-matrix"), target .. " actual Solar Matrix recipe unlock")
      check(data.raw.recipe["solar-matrix"].results[1].name == "solar-matrix", target .. " actual panel manufacturing output")
    end
    if combination.accumulator then
      local owner = combination.matrix and not combination.paracelsin and "solar-matrix" or "accumulator-v2"
      check(unlocks(data.raw.technology[owner],"accumulator-v2"), target .. " accumulator unlock owner " .. owner)
      check(data.raw.recipe["accumulator-v2"].results[1].name == "accumulator-v2", target .. " actual accumulator manufacturing output")
      if combination.matrix and not combination.paracelsin then
        check(not data.raw.technology["accumulator-v2"], target .. " paired mod does not invent an independent accumulator unlock")
      end
    end
    check(settings.startup["solar-matrix-power"].value==128 and settings.startup["accumulator-power-capacity"].value==10,
      target .. " configurable upstream output and capacity settings remain unchanged")
  end
  -- Capture the five actual SE manufacturing declarations without evaluating
  -- unrelated late-file recipes or inventing their dependencies.
  local captured={}
  local util={mod_prefix="se-",make_recipe=function(recipe) captured[recipe.name]=recipe end}
  package.loaded.data_util=util
  package.loaded["prototypes/recipe-tints"]={}
  SEItemNames={get_glass_name=function() return "glass" end}
  local code=selected["space-exploration"].files["prototypes/phase-1/recipe/manufacturing.lua"]
  local start=assert(code:find('\nmake_recipe%(%{\n  name = data_util.mod_prefix %.%. "space%-solar%-panel"'))
  local finish=assert(code:find('\nmake_recipe%(%{\n  name = data_util.mod_prefix %.%. "observation%-frame%-blank"'))
  assert(load('local data_util=require("data_util"); local make_recipe=data_util.make_recipe;\n' .. code:sub(start,finish-1),
    "@" .. selected["space-exploration"].path .. "/manufacturing-slice", "t", _G))()
  for _, name in ipairs({"se-space-solar-panel","se-space-solar-panel-2","se-space-solar-panel-3","se-space-accumulator","se-space-accumulator-2"}) do
    local recipe=captured[name]
    check(recipe and recipe.results[1].name==name, target .. " exact SE producing recipe " .. name)
    local category = recipe.categories and recipe.categories[1] or recipe.category
    check(category=="space-manufacturing", target .. " exact manufacturing category " .. name)
  end
  local aai=selected["aai-industry"]
  local furnace
  for path,code in pairs(aai.files) do
    if path:match("combined/industrial%-furnace.lua$") then furnace=code end
  end
  check(furnace and furnace:find('type = "recipe"') and furnace:find('name = "industrial%-furnace"'), target .. " AAI owns the industrial furnace independently of SE")
end
print("MIR-COMMUNITY-UPSTREAM-PASS " .. checks)

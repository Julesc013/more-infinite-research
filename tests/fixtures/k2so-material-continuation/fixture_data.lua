-- Independent expected rows and one fixture-only probe. The fixture uses the
-- named native `lab` unchanged; it never publishes a widened substitute.
local M = {}
local PREFIX = "mir-k2so-material-continuation"
local PACKS = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "space-science-pack"}
local CAPS = {source=0, upgrade=0, finite=3, relaxed=0}
local MATERIALS = {
  {key="rare_metals", recipes={"kr-rare-metals", "kr-rare-metals-from-enriched-rare-metals"},
    science={PACKS[1],PACKS[2],PACKS[3]},
    prerequisites={PACKS[1],PACKS[2],PACKS[3],"kr-rare-metal-processing","kr-enriched-ores"}},
  {key="silicon", recipes={"kr-silicon"}, science={PACKS[1],PACKS[2]},
    prerequisites={PACKS[1],PACKS[2],"kr-silicon-processing"}},
  {key="glass", recipes={"kr-glass"}, science={PACKS[1],PACKS[2],PACKS[3]},
    prerequisites={PACKS[1],PACKS[2],PACKS[3],"kr-stone-processing"}},
}
local function check(condition,message)
  if not condition then error("[mir-k2so-material-continuation] " .. message,3) end
end
local function id(material,suffix) return "recipe-prod-research_material_" .. material.key .. "-" .. suffix end
local function names(actual,expected,label)
  check(type(actual)=="table" and #actual==#expected,label .. " count differs")
  for index,name in ipairs(expected) do check(actual[index]==name,label .. " identity/order differs") end
end
local function accepts_named_lab(science)
  local lab=data.raw.lab and data.raw.lab.lab
  if type(lab)~="table" or lab.name~="lab" then return false end
  local available={}
  for _,pack in ipairs(lab.inputs or {}) do available[pack]=true end
  for _,pack in ipairs(science) do if not available[pack] then return false end end
  return true
end
local function validate_row(material,late)
  local name=id(material,late and 4 or 1)
  local row=data.raw.technology[name]
  check(type(row)=="table" and row.type=="technology" and row.name==name,"missing material row: " .. name)
  check(row.level==(late and 4 or 1) and row.max_level==(late and "infinite" or 3)
    and row.upgrade==true and row.enabled~=false,"material progression/enablement differs: " .. name)
  local science=late and {PACKS[4]} or material.science
  local prerequisites=late and {id(material,1),PACKS[4]} or material.prerequisites
  names(row.prerequisites,prerequisites,name .. " prerequisites")
  check(type(row.effects)=="table" and #row.effects==#material.recipes,"material effect count differs")
  for index,recipe in ipairs(material.recipes) do
    local effect=row.effects[index]
    check(effect.type=="change-recipe-productivity" and effect.recipe==recipe and effect.change==.02,
      "material effect differs: " .. name)
  end
  local unit=row.unit
  check(type(unit)=="table" and unit.count==nil and unit.count_formula==(late and "1600+200*(L-4)" or "200*2^(L-1)")
    and unit.time==30,"ordinary material cost/time differs: " .. name)
  check(type(unit.ingredients)=="table" and #unit.ingredients==#science,"final material science count differs: " .. name)
  for index,pack in ipairs(science) do
    local ingredient=unit.ingredients[index]
    check(type(ingredient)=="table" and ingredient[1]==pack and ingredient[2]==1,"final material science differs: " .. name)
  end
  check(accepts_named_lab(science),"named original lab does not accept final material science: " .. name)
end

function M.settings(stage)
  local cap=CAPS[stage]
  check(cap~=nil,"unknown settings stage")
  for _,material in ipairs(MATERIALS) do
    local setting=data.raw["int-setting"] and data.raw["int-setting"]["ips-max-level-research_material_" .. material.key]
    check(type(setting)=="table","material cap setting is absent")
    setting.default_value=cap
  end
end

function M.prototypes(stage)
  check(CAPS[stage]~=nil,"unknown prototype stage")
  check(data.raw.technology[PREFIX .. "-probe"]==nil,"fixture probe already exists")
  data:extend{{type="technology",name=PREFIX .. "-probe",icon="__base__/graphics/technology/automation-1.png",
    icon_size=256,effects={},prerequisites={},unit={count=20,time=30,ingredients={{PACKS[1],1}}}}}
end

function M.validate(stage)
  check(CAPS[stage]~=nil,"unknown final stage")
  for _,material in ipairs(MATERIALS) do
    validate_row(material,false)
    if stage=="source" then
      check(data.raw.technology[id(material,4)]==nil,"published source unexpectedly has a material continuation")
    else validate_row(material,true) end
  end
  local source=data.raw.lab.lab
  check(type(source)=="table" and type(source.energy_source)=="table" and source.energy_source.type=="electric",
    "ordinary electric lab prototype is absent")
end

return M

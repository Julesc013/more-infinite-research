-- Runs after exact MIR through info.json. All prototype changes here are
-- controlled fixture mechanism, not a report about any external modpack.
local C=require("contract")
C.target(mods)
local credits=data.raw["mod-data"] and data.raw["mod-data"]["more-infinite-research-native-adoptions"]
C.require(credits and credits.data and type(credits.data.credits)=="table","missing MIR credit transport")
local technologies=data.raw.technology
local function effect(technology,recipe,change)
  for _,row in ipairs(technology.effects or {})do
    if row.type=="change-recipe-productivity" and row.recipe==recipe then
      C.require(C.close(row.change,change),"effect coefficient differs: "..technology.name..":"..recipe)
      return row
    end
  end
end
local function clone_recipe(source,name)
  C.require(data.raw.recipe[name]==nil,"fixture recipe exists: "..name)
  local row=table.deepcopy(data.raw.recipe[source])
  C.require(row and row.type=="recipe" and row.name==source,"source recipe missing: "..source)
  row.name=name;row.enabled=false;row.hidden=true
  data:extend({row})
end
local function append(technology,recipe,change)
  C.require(not effect(technology,recipe,change),"fixture effect exists: "..technology.name..":"..recipe)
  technology.effects[#technology.effects+1]={type="change-recipe-productivity",recipe=recipe,change=change}
end
local function transport(family)
  local rows=credits.data.credits[family.key]
  C.require(type(rows)=="table" and #rows==#family.routes,"MIR route count differs: "..family.key)
  local wanted={}
  for _,name in ipairs(family.routes)do wanted[name]=true end
  for _,row in ipairs(rows)do
    C.require(type(row)=="table" and wanted[row.recipe] and C.close(row.change,.1),"MIR route differs: "..family.key)
    wanted[row.recipe]=nil
  end
  C.require(next(wanted)==nil,"MIR route absent: "..family.key)
end
for _,family in ipairs(C.families)do
  transport(family)
  local main=technologies[C.main(family)]
  local reference=technologies[family.reference]
  C.require(main and reference and reference.hidden~=true,"missing main/reference: "..family.key)
  for _,recipe in ipairs(family.routes)do
    local extra=family.extra[recipe]
    -- Ensure the real public reference still owns the actual route before the
    -- fixture adds any controlled companion or public-only component.
    C.require(effect(reference,recipe,.1),"public reference route differs: "..family.reference..":"..recipe)
    C.require(effect(main,recipe,.1),"MIR main route differs: "..family.key..":"..recipe)
    clone_recipe(recipe,extra)
    append(main,extra,.1)
    append(reference,extra,.1)
    for _,sign in ipairs({"positive","negative"})do
      local holder=technologies[C.carrier(family,recipe,sign)]
      local change=sign=="positive" and .1 or -.1
      C.require(holder and holder.hidden==true and holder.enabled==false and effect(holder,recipe,change)
        and #holder.effects==1,"native carrier baseline differs: "..family.key..":"..recipe..":"..sign)
      append(holder,extra,change)
    end
  end
  clone_recipe(family.routes[1],family.public_only)
  -- This is intentionally on the public reference only. It must never become
  -- a signed carrier component or MIR paid credit.
  append(reference,family.public_only,.1)
end

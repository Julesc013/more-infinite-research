-- Runs after the bounded 5.0.14/5.0.15 MIR dependency through info.json. All prototype changes here are
-- controlled fixture mechanism, not a report about any external modpack.
local C=require("contract")
local _,_,phase=C.phase(mods)
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
local function controlled_recipe(name)
  C.require(data.raw.recipe[name]==nil,"fixture recipe exists: "..name)
  data:extend({{type="recipe",name=name,category="crafting",enabled=true,hidden=true,allow_productivity=true,
    ingredients={{type="item",name=C.physical_input,amount=1}},results={{type="item",name=C.physical_output,amount=1}},
    main_product=C.physical_output,auto_recycle=false}})
end
local function append(technology,recipe,change)
  C.require(not effect(technology,recipe,change),"fixture effect exists: "..technology.name..":"..recipe)
  technology.effects[#technology.effects+1]={type="change-recipe-productivity",recipe=recipe,change=change}
end
local function authored_main(main,family)
  C.require(type(main.unit)=="table" and main.unit.count_formula==C.formula and main.unit.time==C.seconds,
    "authored main unit differs: "..family.key)
  local ingredients,prerequisites={},{}
  for _,row in ipairs(main.unit.ingredients or {})do
    local name,amount=row.name or row[1],row.amount or row[2]
    C.require(type(name)=="string" and amount==1 and ingredients[name]==nil,"authored main science differs: "..family.key)
    ingredients[name]=true
  end
  for _,name in ipairs(C.packs)do C.require(ingredients[name]==true,"authored main science absent: "..family.key..":"..name);ingredients[name]=nil end
  C.require(next(ingredients)==nil,"authored main science extra: "..family.key)
  for _,name in ipairs(main.prerequisites or {})do C.require(type(name)=="string" and prerequisites[name]==nil,"authored main prerequisite differs: "..family.key);prerequisites[name]=true end
  for _,name in ipairs(C.packs)do C.require(prerequisites[name]==true,"authored main prerequisite absent: "..family.key..":"..name);prerequisites[name]=nil end
  C.require(next(prerequisites)==nil,"authored main prerequisite extra: "..family.key)
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
  C.require(main,"missing main: "..family.key)
  authored_main(main,family)
  -- Stock Space Age has retained this MIR continuation privately with no
  -- current effects. The fixture exposes a controlled three-phase mask only
  -- after observing that exact baseline; it never assumes the host already
  -- published the current native routes on the MIR main.
  C.require(main.hidden==true and #main.effects==0,"stock MIR main baseline differs: "..family.key
    .." hidden="..tostring(main.hidden).." effects="..tostring(#main.effects))
  main.effects={};main.hidden=false;main.enabled=true
  for _,recipe in ipairs(family.routes)do
    local extra=family.extra[recipe]
    local public_only=family.public_only[recipe]
    local reference_name=C.reference(family,recipe)
    local reference=technologies[reference_name]
    C.require(reference and reference.hidden~=true,"missing public reference: "..family.key..":"..recipe)
    -- Ensure the real public reference still owns the actual route before the
    -- fixture adds any controlled companion or public-only component.
    C.require(effect(reference,recipe,.1),"public reference route differs: "..reference_name..":"..recipe)
    controlled_recipe(extra)
    append(reference,extra,.1)
    for _,sign in ipairs({"positive","negative"})do
      local holder=technologies[C.carrier(family,recipe,sign)]
      local change=sign=="positive" and .1 or -.1
      C.require(holder and holder.hidden==true and holder.enabled==false and effect(holder,recipe,change)
        and #holder.effects==1,"native carrier baseline differs: "..family.key..":"..recipe..":"..sign)
      append(holder,extra,change)
    end
    if phase=="F1"then
      -- This controlled F1 mask is a complete, named counterpart to the
      -- exact signed holder. F0 carries no basis; F2 retires it again.
      append(main,recipe,.1);append(main,extra,.1)
    end
    controlled_recipe(public_only)
    -- Every controlled public-only component stays exclusively on the foreign
    -- reference selected for this exact carrier route. In particular, Scrap
    -- retains its independently authored productivity reference.
    append(reference,public_only,.1)
  end
  if phase=="F2"then main.effects={};main.hidden=true;main.enabled=false end
end

local M = {}
M.packs = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "military-science-pack", "utility-science-pack"}
M.gates = {"research-speed-6", "research-speed-7"}
for _, name in ipairs(M.packs) do M.gates[#M.gates + 1] = name end

local function close(a, b) return type(a)=="number" and type(b)=="number" and math.abs(a-b)<1e-7 end
M.close = close
local function same(rows, names, label, ingredient)
  assert(type(rows)=="table" and #rows==#names, label .. " count differs")
  for index, name in ipairs(names) do
    local row=rows[index]
    assert((ingredient and type(row)=="table" and row[1]==name and row[2]==1)
      or (not ingredient and row==name), label .. " differs at " .. index)
  end
end
local function effect(value, label)
  assert(type(value.effects)=="table" and #value.effects==1 and value.effects[1].type=="laboratory-speed"
    and close(value.effects[1].modifier,.6),label .. " effect differs")
end
function M.prototypes(technologies)
  local seven, eight=assert(technologies["research-speed-7"]),assert(technologies["research-speed-8"])
  assert(seven.level==7 and seven.max_level==nil and seven.unit.count==777
    and seven.unit.count_formula==nil and seven.unit.time==77,"foreign7 cost/identity differs")
  effect(seven,"foreign7")
  same(seven.prerequisites,{"research-speed-6"},"foreign7 prerequisite")
  same(seven.unit.ingredients,{"automation-science-pack"},"foreign7 science",true)
  assert(eight.level==8 and eight.max_level=="infinite" and eight.unit.count==nil
    and eight.unit.count_formula=="1025.15625*1.5^(L-8)" and eight.unit.time==120,"MIR8 cost/identity differs")
  effect(eight,"MIR8")
  same(eight.prerequisites,M.gates,"MIR8 prerequisites")
  same(eight.unit.ingredients,M.packs,"MIR8 science",true)
end

function M.queue(force)
  local queue={}
  for index,technology in ipairs(force.research_queue or {}) do queue[index]=technology.name end
  return {current=force.current_research and force.current_research.name or false,
    progress=force.research_progress,queue=queue}
end
function M.snapshot(force)
  local seven,eight=assert(force.technologies["research-speed-7"]),assert(force.technologies["research-speed-8"])
  return {seven_level=seven.level,seven_researched=seven.researched,seven_enabled=seven.enabled,
    seven_visible=seven.visible_when_disabled,eight_level=eight.level,eight_researched=eight.researched,
    eight_enabled=eight.enabled,eight_visible=eight.visible_when_disabled,eight_saved=eight.saved_progress,
    bonus=force.laboratory_speed_modifier,queue=M.queue(force)}
end
function M.preserved(actual, expected)
  assert(type(expected)=="table","saved snapshot absent")
  for _,key in ipairs({"seven_level","seven_researched","seven_enabled","seven_visible",
      "eight_level","eight_researched","eight_enabled","eight_visible"}) do
    assert(actual[key]==expected[key],key .. " changed")
  end
  for _,key in ipairs({"eight_saved","bonus"}) do assert(close(actual[key],expected[key]),key .. " changed") end
  assert(actual.queue.current==expected.queue.current and close(actual.queue.progress,expected.queue.progress)
    and #actual.queue.queue==#expected.queue.queue,"current research/progress/queue changed")
  for index,name in ipairs(expected.queue.queue) do assert(actual.queue.queue[index]==name,"queue order changed") end
end
return M

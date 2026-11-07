-- Independent retained contract and source witness from private commit 6c1e5d7673dff1667dabe0122058151fc6f5536f; target/fixture admission only is updated.
local M={mir="more-infinite-research",fixture="mir-fixture-mixed-gun504-first-entry",
 source="5.0.21003",target="5.0.21008",main="recipe-prod-research_electric_shooting_speed-1",
 owner="laser-shooting-speed-8",detached="recipe-prod-research_rocket_shooting_speed-1",
 forces={"mixed504-paid-two","mixed504-paid-three","mixed504-unearned-disabled"},
 categories={"electric","tesla","laser","rocket"}}
M.holders={electric={positive="mir-native-credit-research_electric_shooting_speed-electric-positive",
 negative="zz-mir-native-credit-research_electric_shooting_speed-electric-negative"},
 tesla={positive="mir-native-credit-research_electric_shooting_speed-tesla-positive",
 negative="zz-mir-native-credit-research_electric_shooting_speed-tesla-negative"}}
function M.copy(a) if type(a)~="table" then return a end local b={};for k,v in pairs(a)do b[k]=M.copy(v)end;return b end
function M.same(a,b,path)
 path=path or "state";assert(type(a)==type(b),path.." type")
 if type(a)=="table"then for k,v in pairs(a)do M.same(v,b[k],path.."."..tostring(k))end;for k in pairs(b)do assert(a[k]~=nil,path.." extra "..tostring(k))end
 elseif type(a)=="number"then assert(a==a and b==b and math.abs(a-b)<1e-8,path.." number")else assert(a==b,path.." value")end
end
function M.owner_definition()
 return {type="technology",name=M.owner,icon="__base__/graphics/technology/weapon-shooting-speed-3.png",icon_size=256,
 level=8,max_level="infinite",upgrade=true,enabled=true,prerequisites={"laser-shooting-speed-7"},
 unit={count_formula="100*2^(L-8)",time=30,ingredients={{"automation-science-pack",1}}},
 effects={{type="gun-speed",ammo_category="laser",modifier=.4},{type="gun-speed",ammo_category="tesla",modifier=.5}}}
end
function M.expected_holders(paid)
 return {electric={positive=0,negative=0},tesla={positive=paid,negative=0}}
end
local witness=require("source-witness") -- Parse-time only; exact published input.
local active=(script and script.active_mods) or mods or {}
M.version=assert(active[M.fixture],"fixture selection absent")
assert(M.version=="0.6.0" or M.version=="0.7.0" or M.version=="0.8.0","unexpected cost-transition phase")
M.target=M.version=="0.8.0" and "5.0.21009" or "5.0.21008"
M.source_version=M.source;M.old_key="mixed_gun504_first_entry_r01";M.key="mixed_gun504_real_lab_r01"
M.lab="mir-mixed-gun504-real-lab";M.surface="mir-mixed-gun504-real-lab-r01"
M.lab_count=4;M.speed=60;M.supply=30;M.max_ticks=5000
M.science={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","military-science-pack","electromagnetic-science-pack"}
function M.source_states()return M.copy(witness)end
function M.entry()return M.source_states()end
function M.mods()return {base="2.1.23",quality="2.1.23",recycler="2.1.23",["elevated-rails"]="2.1.23",["space-age"]="2.1.23",[M.mir]=M.target,[M.fixture]=M.version}end
function M.old_fixture()return {phase="target-ready",expected=M.source_states(),entry_tick=1}end
function M.post(progress,price)
 local allowance=M.lab_count*M.speed/1800/price
 assert(progress>=.19-1e-8 and progress<=.19+allowance+1e-8,"foreign queued partial outside one-tick work bound")
 local out=M.entry();local f=out[1]
 f.main.level=4;f.owner.saved=0;f.current=M.owner;f.queue={M.owner};f.progress=progress
 f.bonuses.electric=f.bonuses.electric+.1 -- Tesla remains exactly previously paid.
 return out
end
function M.position(i)return {x=-4.5+((i-1)%2)*9,y=-4.5+math.floor((i-1)/2)*9}end
return M

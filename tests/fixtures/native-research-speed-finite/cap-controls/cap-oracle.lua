-- Independent SET-03/RUN-02 expectations, not a candidate-state projection.
-- Above-cap current work is detached on its native technology; queued intent
-- is cancelled, never journalled/restored. Uncapping releases MIR's own flag.
local M={}
local function copy(value)
  if type(value)~="table" then return value end
  local out={};for key,item in pairs(value) do out[key]=copy(item) end;return out
end
function M.expected(unbounded,cap)
  assert(cap==0 or cap==8,"unexpected cap boundary")
  local expected=copy(unbounded)
  assert(expected.eight_level==9 and expected.eight_enabled
    and expected.queue.current=="research-speed-8" and #expected.queue.queue==2
    and expected.queue.queue[2]=="automation" and math.abs(expected.queue.progress-.42)<1e-7,
    "independent boundary baseline differs")
  expected.eight_enabled=cap==0
  expected.eight_visible=cap==8 or unbounded.eight_visible
  expected.eight_saved=.42
  expected.queue={current="automation",progress=0,queue={"automation"}}
  return expected
end
return M

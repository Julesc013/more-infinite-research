-- Failure-only observation of this exact finalized environment. These facts
-- are post-MIR inputs, not a pre-compiler capture or a gameplay acceptance.
local function observe_missing_tin()
  local prefix = "__more-infinite-research__.prototypes.mir."
  local compiler_context = require(prefix .. "pipeline.compiler_context")
  local science = require(prefix .. "capabilities.science_integration.science_packs")
  local production = science.pack_production_reachability
  local recipe_facts = require(prefix .. "index.recipe_facts")
  for _, name in ipairs({"bob-burner-lab", "lab", "bob-glass", "bob-quartz", "stone-furnace", "wood", "iron-plate"}) do
    compiler_context.with_active(compiler_context.new({execution_mode="SAFE"}), function()
      science.ensure_services()
      recipe_facts.index_view()
      local observer = {visits=0, failures={}, stopped=false}
      function observer:is_stopped() return self.stopped end
      function observer:reserve_visit(depth)
        self.visits = self.visits + 1
        if self.visits > 200000 or depth > 96 then self.stopped = true end
        return not self.stopped
      end
      function observer:record(failure, depth)
        if #self.failures < 30 then self.failures[#self.failures+1] = {depth=depth, failure=failure} end
      end
      function observer:checkpoint() return #self.failures end
      function observer:rollback(count)
        while #self.failures > count do self.failures[#self.failures] = nil end
      end
      local witness = production.item_acquisition_witness(name, {}, {}, observer)
      log("[mir-tin-acquisition-diagnostic] " .. serpent.line({item=name,
        witness_kind=witness and witness.kind, visits=observer.visits,
        indeterminate=observer.stopped, failures=observer.failures,
        recipe=data.raw.recipe[name]}, {comment=false}))
    end)
  end
  for _, name in ipairs({"bob-burner-lab", "bob-lab", "automation-science-pack", "electronics"}) do
    local technology = data.raw.technology[name]
    log("[mir-tin-acquisition-diagnostic] " .. serpent.line({technology=name,
      prerequisites=technology and technology.prerequisites,
      research_trigger=technology and technology.research_trigger,
      unit=technology and technology.unit, effects=technology and technology.effects}, {comment=false}))
  end
end

local early_name = "recipe-prod-research_material_tin-1"
local continuation_name = "recipe-prod-research_material_tin-4"
local recipe_name = "bob-tin-plate"

local function fail(message)
  error("[mir-f210-current-bob-tin-level4] " .. message)
end

local function effect_change(technology)
  local count, change = 0, nil
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      count = count + 1
      change = effect.change
    end
  end
  if count ~= 1 or change ~= 0.02 then
    fail("technology productivity effect differs " .. technology.name .. " count="
      .. tostring(count) .. " change=" .. tostring(change))
  end
  return change
end

local function has_value(values, expected)
  for _, value in ipairs(values or {}) do
    if value == expected then return true end
  end
  return false
end

local function science_names(technology)
  local unit = technology.unit
  if type(unit) ~= "table" or type(unit.ingredients) ~= "table" or #unit.ingredients == 0 then
    fail("continuation science ingredients are absent")
  end
  local lab = data.raw.lab and data.raw.lab.lab
  if type(lab) ~= "table" or type(lab.inputs) ~= "table" then
    fail("base lab inputs are absent")
  end
  local names = {}
  for _, ingredient in ipairs(unit.ingredients) do
    local name = ingredient.name or ingredient[1]
    local amount = ingredient.amount or ingredient[2]
    if type(name) ~= "string" or type(amount) ~= "number" or amount <= 0 then
      fail("continuation science ingredient shape differs")
    end
    if not has_value(lab.inputs, name) then
      fail("base lab does not accept continuation science " .. name)
    end
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

local early = data.raw.technology[early_name]
local continuation = data.raw.technology[continuation_name]
if type(early) ~= "table" or early.max_level ~= 3 then
  observe_missing_tin()
  fail("finite legacy Tin technology differs")
end
if type(continuation) ~= "table" or continuation.level ~= 4 or continuation.max_level ~= "infinite" then
  fail("level-four Tin continuation differs")
end
if not has_value(continuation.prerequisites, early_name) then
  fail("level-four Tin continuation does not require the finite legacy technology")
end
effect_change(early)
effect_change(continuation)
local science = science_names(continuation)
log("[mir-f210-current-bob-tin-level4] DATA PASS"
  .. " early=" .. early_name .. ":1:3"
  .. " continuation=" .. continuation_name .. ":4:infinite"
  .. " prerequisite=true"
  .. " science=" .. table.concat(science, ",")
  .. " lab-compatible=true")

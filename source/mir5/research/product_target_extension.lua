-- Extend already-authored productivity definitions with the retained literal
-- product targeting contract. Collection selects recipes only; identity,
-- progression, science and existing effects remain with their authors.
local M = {}

local function eligible_family(row, values)
  if type(row) ~= "table" or type(row.name) ~= "string" then return nil end
  local family = row.name:match("^recipe%-prod%-(.+)%-1$")
  if family == nil or type(row.effects) ~= "table" or #row.effects == 0 then return nil end
  for _, effect in ipairs(row.effects) do
    if effect.type ~= "change-recipe-productivity" then return nil end
  end
  local stream = values.streams and values.streams[family]
  if stream == nil and family == "research_gears" then stream = values end
  if type(stream) ~= "table" or type(stream.effect_percent) ~= "number" then return nil end
  return family, stream
end

function M.extend(technologies, values, context)
  local selected, streams, count = {}, {}, 0
  for _, row in ipairs(technologies) do
    local family, stream = eligible_family(row, values)
    if family then
      assert(selected[family] == nil, "MIR duplicate product target family " .. family)
      selected[family], streams[family], count = row, stream, count + 1
    end
  end
  local report = {extended_effects=0, families=0,
    work={recipes=0, products=0, ingredients=0, matches=0}}
  if count == 0 then return report end

  -- Import declarations only for an applicable catalogue. No reusable global
  -- cache: this sole final-fixes call sees the current recipe tables.
  local bindings = require("compatibility.product_bindings")
  local rules = {}
  local function admit(rows)
    for _, row in ipairs(rows) do
      if selected[row.family] and (not row.structural_fallback
        or require("compatibility.automatic_productivity").applies(values.options)) then
        rules[#rules + 1] = row
      end
    end
  end
  admit(bindings.base.bindings)
  if context.mods and context.mods["space-age"] then admit(bindings.space_age.bindings) end
  if selected.research_science_pack_productivity and context.mods and context.mods.Krastorio2
    and require("compatibility.modern_catalogue").is_k2so(context.mods) then
    admit(require("compatibility.modern_catalogue.k2so").product_bindings)
  end
  local module_count = 0
  if selected.research_modules then
    local module_rules
    module_rules, module_count = bindings.module_tier_bindings(context.raw.module)
    admit(module_rules)
  end
  if #rules == 0 then return report end

  local collector = require("compatibility.product_targets")
  local result = collector.collect(context.raw.recipe, collector.prepare(rules, {raw=context.raw}))
  report.work = result.work
  report.work.modules = module_count
  for family, rows in pairs(result.by_family) do
    local technology = selected[family]
    local effects, seen = technology.effects, {}
    for _, effect in ipairs(effects) do seen[effect.recipe] = true end
    local added = false
    for _, row in ipairs(rows) do
      if not seen[row.recipe] then
        effects[#effects + 1] = {type="change-recipe-productivity", recipe=row.recipe,
          change=streams[family].effect_percent * row.weight / 100}
        seen[row.recipe], added = true, true
        report.extended_effects = report.extended_effects + 1
      end
    end
    if added then report.families = report.families + 1 end
  end
  return report
end

return M

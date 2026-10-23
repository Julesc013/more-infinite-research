-- Extend already-authored productivity definitions with the retained literal
-- product targeting contract. Collection selects recipes only; identity,
-- progression, science and existing effects remain with their authors.
local M = {}

local function diagnostic_writer(values, context)
  local options = values and values.options
  if type(options) ~= "table" or options["mir-debug-recipe-matches"] ~= true then return nil end
  return context and type(context.log) == "function" and context.log or nil
end

local function automatic_action(values)
  local options = values and values.options
  if type(options) ~= "table" then return "apply" end
  return options["mir-automatic-productivity-action"] or "apply"
end

local function emit_preview_disposition(values, context)
  if automatic_action(values) ~= "preview" then return end
  local write = context and type(context.log) == "function" and context.log or nil
  if write then
    -- MIR5 retains no discovery compiler or automatic identities. This one
    -- line makes the old preview control honest about the bounded decision.
    write("[more-infinite-research] automatic-productivity preview: no automatic research identities; structural-fallback bindings withheld")
  end
end

local function emit_diagnostics(write, report)
  if not write then return end
  write("[more-infinite-research] recipe-targets report start")
  write("[more-infinite-research] recipe-targets decision structural-fallbacks="
    .. (report.structural_fallbacks and "included" or "withheld")
    .. " action=" .. report.action
    .. " selected-families=" .. tostring(report.selected_families)
    .. " rules=" .. tostring(report.rules))
  local work = report.work
  write("[more-infinite-research] recipe-targets work recipes=" .. tostring(work.recipes)
    .. " products=" .. tostring(work.products)
    .. " ingredients=" .. tostring(work.ingredients)
    .. " matches=" .. tostring(work.matches)
    .. " modules=" .. tostring(work.modules or 0))
  for _, match in ipairs(report.matches or {}) do
    write("[more-infinite-research] recipe-target match family=" .. match.family
      .. " recipe=" .. match.recipe
      .. " product=" .. match.product_type .. ":" .. match.product_name
      .. " weight=" .. tostring(match.weight)
      .. " disposition=" .. match.disposition)
  end
  write("[more-infinite-research] recipe-targets report end")
end

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
  local write = diagnostic_writer(values, context)
  local action = automatic_action(values)
  local automatic = false
  local report = {extended_effects=0, families=0, rules=0, selected_families=count,
    structural_fallbacks=automatic, action=action,
    work={recipes=0, products=0, ingredients=0, matches=0, modules=0}}
  emit_preview_disposition(values, context)
  if count == 0 then
    emit_diagnostics(write, report)
    return report
  end

  automatic = require("compatibility.automatic_productivity").applies(values.options)
  report.structural_fallbacks = automatic

  -- Import declarations only for an applicable catalogue. No reusable global
  -- cache: this sole final-fixes call sees the current recipe tables.
  local bindings = require("compatibility.product_bindings")
  local rules = {}
  local function admit(rows)
    for _, row in ipairs(rows) do
      if selected[row.family] and (not row.structural_fallback
        or automatic) then
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
  report.rules = #rules
  if #rules == 0 then
    emit_diagnostics(write, report)
    return report
  end

  local collector = require("compatibility.product_targets")
  local result = collector.collect(context.raw.recipe, collector.prepare(rules, {raw=context.raw}))
  report.work = result.work
  report.work.modules = module_count
  local dispositions = write and {} or nil
  for family, rows in pairs(result.by_family) do
    local technology = selected[family]
    local effects, seen = technology.effects, {}
    for _, effect in ipairs(effects) do seen[effect.recipe] = true end
    local added = false
    for _, row in ipairs(rows) do
      local key
      if write then key = family .. "\0" .. row.recipe .. "\0" .. row.product_type .. "\0" .. row.product_name end
      if not seen[row.recipe] then
        effects[#effects + 1] = {type="change-recipe-productivity", recipe=row.recipe,
          change=streams[family].effect_percent * row.weight / 100}
        seen[row.recipe], added = true, true
        report.extended_effects = report.extended_effects + 1
        if write then dispositions[key] = "added" end
      elseif write then
        dispositions[key] = "already-present"
      end
    end
    if added then report.families = report.families + 1 end
  end
  if write then
    report.matches = {}
    -- `collector.collect` has already sorted these current-pass targets. Emit
    -- exactly that order instead of traversing the family maps a second time.
    for _, row in ipairs(result.targets) do
      local key = row.family .. "\0" .. row.recipe .. "\0" .. row.product_type .. "\0" .. row.product_name
      report.matches[#report.matches + 1] = {
        family=row.family, recipe=row.recipe, product_type=row.product_type,
        product_name=row.product_name, weight=row.weight,
        disposition=dispositions[key] or "withheld"
      }
    end
  end
  emit_diagnostics(write, report)
  return report
end

return M

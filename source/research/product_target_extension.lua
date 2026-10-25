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
    .. " modules=" .. tostring(work.modules or 0)
    .. " labs=" .. tostring(work.labs or 0) .. " lab-inputs=" .. tostring(work.lab_inputs or 0))
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

local function selected_family_set(value, label)
  if value == nil then return {} end
  if type(value) ~= "table" then error("MIR product targets has invalid " .. label, 3) end
  local out = {}
  for family, selected in pairs(value) do
    if type(family) ~= "string" or family == "" or selected ~= true then
      error("MIR product targets has invalid " .. label, 3)
    end
    out[family] = true
  end
  return out
end

-- A profile can retain the same authored family while replacing its inherited
-- Base recipe vector with the current, bounded collector result.  This is
-- deliberately a family set, not a request to discover another family.
local function replacement_family_set(value)
  return selected_family_set(value, "replacement product target families")
end

-- Profile deltas sometimes withhold one known recipe from an otherwise shared
-- product family.  Keep that decision as exact family/recipe data; patterns
-- and broad post-collection classifiers would change the collector contract.
local function excluded_target_recipes(value)
  if value == nil then return {} end
  if type(value) ~= "table" then error("MIR product targets has invalid excluded target recipes", 3) end
  local out = {}
  for family, names in pairs(value) do
    if type(family) ~= "string" or family == "" or type(names) ~= "table" then
      error("MIR product targets has invalid excluded target recipes", 3)
    end
    local selected, count = {}, 0
    for index, name in ipairs(names) do
      if type(name) ~= "string" or name == "" or selected[name] then
        error("MIR product targets has invalid excluded target recipes", 3)
      end
      selected[name], count = true, count + 1
    end
    if count ~= #names or count == 0 then error("MIR product targets has invalid excluded target recipes", 3) end
    out[family] = selected
  end
  return out
end

local function expected_target_lists(value)
  if value == nil then return {} end
  if type(value) ~= "table" then error("MIR product targets has invalid required targets", 3) end
  local out = {}
  for family, recipes in pairs(value) do
    if type(family) ~= "string" or family == "" or type(recipes) ~= "table" then
      error("MIR product targets has invalid required targets", 3)
    end
    local seen, names = {}, {}
    for index, recipe in ipairs(recipes) do
      if type(recipe) ~= "string" or recipe == "" or seen[recipe] then
        error("MIR product targets has invalid required targets", 3)
      end
      seen[recipe], names[index] = true, recipe
    end
    if #names == 0 then error("MIR product targets has invalid required targets", 3) end
    table.sort(names)
    out[family] = names
  end
  return out
end

local function verify_required_targets(result, required)
  for family, expected in pairs(required) do
    local actual, names = result.by_family[family] or {}, {}
    for _, row in ipairs(actual) do names[#names + 1] = row.recipe end
    if #names ~= #expected then error("MIR product targets changed required family " .. family, 3) end
    for index, name in ipairs(expected) do
      if names[index] ~= name then error("MIR product targets changed required family " .. family, 3) end
    end
  end
end

-- Preserve the authored science family's dynamic lab-input targets. This
-- collects only typed products; the existing recipe pass still selects every
-- producer and applies its ordinary yield, denial and recycling safeguards.
local function lab_science_binding(raw)
  local names, seen, lab_count, input_count = {}, {}, 0, 0
  local collector = require("compatibility.product_targets")
  for _, lab in pairs(raw and raw.lab or {}) do
    lab_count = lab_count + 1
    if type(lab) == "table" and type(lab.inputs) == "table" then
      for _, name in ipairs(lab.inputs) do
        input_count = input_count + 1
        if type(name) == "string" and name ~= "" and not seen[name] then
          seen[name] = true
          if collector.item_exists(raw, name) then names[#names + 1] = name end
        end
      end
    end
  end
  if #names == 0 then return nil, lab_count, input_count end
  table.sort(names)
  local products = {}
  for index, name in ipairs(names) do products[index] = {type="item", name=name} end
  return {family="research_science_pack_productivity", weight=1,
    reject_explicit_productivity_denial=true, products=products}, lab_count, input_count
end

-- The modern science family's literal seeds represent current lab-input item
-- identities. Its one collector pass below owns additional producers. Remove
-- only such a seed whose named recipe was actually removed; a present malformed
-- target remains for Generator's strict preflight rather than being hidden here.
-- Exact and declared replacement families retain their caller-owned vectors.
local function remove_missing_science_effects(technology, raw, products)
  local recipes = type(raw) == "table" and raw.recipe or nil
  if type(recipes) ~= "table" then return end
  local inputs = {}
  for _, product in ipairs(products or {}) do
    if type(product) == "table" and product.type == "item" and type(product.name) == "string"
      and product.name ~= "" then inputs[product.name] = true end
  end
  local effects = technology.effects
  for index = #effects, 1, -1 do
    local recipe = effects[index].recipe
    if type(recipe) == "string" and recipe ~= "" and inputs[recipe] and recipes[recipe] == nil then
      table.remove(effects, index)
    end
  end
end

function M.extend(technologies, values, context)
  context = context or {}
  local exact_families = selected_family_set(context.exact_product_target_families, "exact product target families")
  local replacement_families = replacement_family_set(context.replacement_product_target_families)
  local excluded_recipes = excluded_target_recipes(context.excluded_product_target_recipes)
  local required_targets = expected_target_lists(context.required_product_targets)
  local selected, streams, count = {}, {}, 0
  for _, row in ipairs(technologies) do
    local family, stream = eligible_family(row, values)
    if family then
      assert(selected[family] == nil, "MIR duplicate product target family " .. family)
      selected[family], streams[family], count = row, stream, count + 1
    end
  end
  for family in pairs(replacement_families) do
    local technology = selected[family]
    if technology then
      -- `technologies` is the detached generated output.  Replacing this one
      -- declared effect vector neither changes the input definitions nor starts
      -- another recipe pass.  A partial consumer may intentionally omit an
      -- unrelated declared family, so it has nothing to replace here.
      technology.effects = {}
    end
  end
  local write = diagnostic_writer(values, context)
  local action = automatic_action(values)
  local automatic = false
  local report = {extended_effects=0, families=0, rules=0, selected_families=count,
    structural_fallbacks=automatic, action=action,
    work={recipes=0, products=0, ingredients=0, matches=0, modules=0, labs=0, lab_inputs=0}}
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
  local function admit(rows, exact)
    for _, row in ipairs(rows) do
      if selected[row.family] and (exact or not exact_families[row.family]) and (not row.structural_fallback
        or automatic) then
        rules[#rules + 1] = row
      end
    end
  end
  admit(bindings.base.bindings)
  if context.mods and context.mods["space-age"] then admit(bindings.space_age.bindings) end
  local lab_count, input_count, lab_rule = 0, 0, nil
  if selected.research_science_pack_productivity and not exact_families.research_science_pack_productivity then
    lab_rule, lab_count, input_count = lab_science_binding(context.raw)
    if lab_rule then admit({lab_rule}) end
  end
  if context.additional_product_bindings ~= nil then
    if type(context.additional_product_bindings) ~= "table" then
      error("MIR selected product bindings are malformed", 2)
    end
    admit(context.additional_product_bindings)
  end
  if context.exact_product_bindings ~= nil then
    if type(context.exact_product_bindings) ~= "table" then
      error("MIR selected exact product bindings are malformed", 2)
    end
    admit(context.exact_product_bindings, true)
  end
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
  report.work.labs, report.work.lab_inputs = lab_count, input_count
  if #rules == 0 then
    emit_diagnostics(write, report)
    return report
  end

  local collector = require("compatibility.product_targets")
  local result = collector.collect(context.raw.recipe, collector.prepare(rules, {raw=context.raw}))
  verify_required_targets(result, required_targets)
  report.work = result.work
  report.work.modules = module_count
  report.work.labs, report.work.lab_inputs = lab_count, input_count
  local dispositions = write and {} or nil
  for family, rows in pairs(result.by_family) do
    local technology = selected[family]
    if family == "research_science_pack_productivity" and not exact_families[family]
      and not replacement_families[family] and lab_rule then
      remove_missing_science_effects(technology, context.raw, lab_rule.products)
    end
    local effects, seen = technology.effects, {}
    if replacement_families[family] then
      -- Published profile groups are ordered by their authored productivity
      -- weight, then the named recipe.  The shared collector itself keeps a
      -- recipe-global order for diagnostics; only a declared rebuilt vector
      -- needs this presentation order.
      table.sort(rows, function(left, right)
        if left.weight ~= right.weight then return left.weight > right.weight end
        if left.recipe ~= right.recipe then return left.recipe < right.recipe end
        if left.product_type ~= right.product_type then return left.product_type < right.product_type end
        return left.product_name < right.product_name
      end)
    end
    for _, effect in ipairs(effects) do seen[effect.recipe] = true end
    local added = false
    for _, row in ipairs(rows) do
      local key
      if write then key = family .. "\0" .. row.recipe .. "\0" .. row.product_type .. "\0" .. row.product_name end
      if excluded_recipes[family] and excluded_recipes[family][row.recipe] then
        if write then dispositions[key] = "withheld" end
      elseif not seen[row.recipe] then
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

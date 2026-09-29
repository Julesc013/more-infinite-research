-- Package-excluded, read-only evidence capture for the current F210
-- Bob/Angel tuple. This fixture observes possible ordinary Angel finals; it
-- does not declare routes, alter recipe permissions, or emit technologies.
local compiler_context = require("__more-infinite-research__/prototypes/mir/pipeline/compiler_context")
local data_raw = require("__more-infinite-research__/prototypes/mir/platform/factorio/data_raw")
local recipe_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_facts")
local recipe_risk_facts = require("__more-infinite-research__/prototypes/mir/index/recipe_risk_facts")
local recipe_matching = require("__more-infinite-research__/prototypes/mir/capabilities/recipe_productivity/recipe_matching")
local relationships = require("__more-infinite-research__/prototypes/mir/index/relationships")

-- These are candidates from the separately retained F200 closure, not an
-- assertion that the F210 graph is equivalent or that any route is admissible.
local CANDIDATES = {
  {family="aluminium", shape="cast-roll", name="angels-plate-aluminium"},
  {family="aluminium", shape="cast-roll", name="angels-plate-aluminium-2"},
  {family="gold", shape="cast-roll", name="angels-plate-gold"},
  {family="gold", shape="cast-roll", name="angels-plate-gold-2"},
  {family="gold", shape="wire", name="angels-wire-gold-2"},
  {family="lead", shape="cast-roll", name="angels-plate-lead"},
  {family="lead", shape="cast-roll", name="angels-plate-lead-2"},
  {family="nickel", shape="cast-roll", name="angels-plate-nickel"},
  {family="nickel", shape="cast-roll", name="angels-plate-nickel-2"},
  {family="silver", shape="cast-roll", name="angels-plate-silver"},
  {family="silver", shape="cast-roll", name="angels-plate-silver-2"},
  {family="silver", shape="wire", name="angels-wire-silver-2"},
  {family="titanium", shape="cast-roll", name="angels-plate-titanium"},
  {family="titanium", shape="cast-roll", name="angels-plate-titanium-2"},
  {family="zinc", shape="cast-roll", name="angels-plate-zinc"},
  {family="zinc", shape="cast-roll", name="angels-plate-zinc-2"},
  {family="brass", shape="molten-alloy", name="angels-plate-brass"},
  {family="bronze", shape="molten-alloy", name="angels-plate-bronze"},
  {family="cobalt-steel", shape="molten-alloy", name="angels-plate-cobalt-steel"},
  {family="gunmetal", shape="molten-alloy", name="angels-plate-gunmetal"},
  {family="invar", shape="molten-alloy", name="angels-plate-invar"},
  {family="nitinol", shape="molten-alloy", name="angels-plate-nitinol"}
}

local ENTRY_FIELDS = {
  "type", "name", "amount", "amount_min", "amount_max", "probability",
  "independent_probability", "declared_probability", "declared_independent_probability",
  "shared_probability", "extra_count_fraction", "catalyst_amount",
  "ignored_by_productivity", "ignored_by_stats", "temperature",
  "minimum_temperature", "maximum_temperature", "fluidbox_index",
  "percent_spoiled", "always_fresh", "reset_freshness_on_craft",
  "quality_min", "quality_max", "quality_change", "affected_by_quality"
}

local function scalar(value)
  if value == nil then return "-" end
  if type(value) == "boolean" then return value and "true" or "false" end
  return tostring(value)
end

local function names_line(values)
  local out = {}
  for _, value in ipairs(values or {}) do out[#out + 1] = tostring(value) end
  table.sort(out)
  return #out == 0 and "-" or table.concat(out, ",")
end

local function entry_line(entries)
  local output = {}
  for _, entry in ipairs(entries or {}) do
    local fields = {}
    for _, field in ipairs(ENTRY_FIELDS) do
      if entry[field] ~= nil then fields[#fields + 1] = field .. "=" .. scalar(entry[field]) end
    end
    output[#output + 1] = "{" .. table.concat(fields, ";") .. "}"
  end
  return #output == 0 and "-" or table.concat(output, "|")
end

local function identity(entry)
  return (entry.type or "item") .. ":" .. tostring(entry.name)
end

local function technology_binding(name)
  local technology = data_raw.technology(name)
  if type(technology) ~= "table" or type(technology.unit) ~= "table" then return name .. "[missing]" end
  local science, prerequisites = {}, {}
  for _, entry in ipairs(technology.unit.ingredients or {}) do
    science[#science + 1] = tostring(entry.name or entry[1]) .. ":" .. tostring(entry.amount or entry[2])
  end
  for _, prerequisite in ipairs(technology.prerequisites or {}) do prerequisites[#prerequisites + 1] = prerequisite end
  return name .. "[" .. names_line(science) .. "][" .. names_line(prerequisites) .. "]"
end

local function active_mods_line()
  local values = {}
  for name, version in pairs(mods or {}) do values[#values + 1] = name .. "=" .. tostring(version) end
  return names_line(values)
end

local function direct_output_producers(fact, index)
  local outputs, names = {}, {}
  for _, variant in ipairs(fact.variants or {}) do
    for _, result in ipairs(variant.results or {}) do outputs[identity(result)] = true end
  end
  for name, candidate in pairs(index.facts or {}) do
    local matches = false
    for _, variant in ipairs(candidate.variants or {}) do
      for _, result in ipairs(variant.results or {}) do
        if outputs[identity(result)] then matches = true; break end
      end
      if matches then break end
    end
    if matches then names[#names + 1] = name end
  end
  return names_line(names)
end

local function observe_bindings(name, input)
  local owners, unlocks = {}, {}
  for _, owner in ipairs((input.technologies_by_recipe_effect or {})[name] or {}) do owners[#owners + 1] = owner end
  for _, unlock in ipairs((input.unlocks_by_recipe or {})[name] or {}) do unlocks[#unlocks + 1] = technology_binding(unlock) end
  log("[mir-f210-current-ba-final-observer] BINDING recipe=" .. name
    .. " owners=" .. names_line(owners) .. " unlocks=" .. names_line(unlocks))
end

local function observe_variants(name, fact)
  for ordinal, variant in ipairs(fact.variants or {}) do
    log("[mir-f210-current-ba-final-observer] VARIANT recipe=" .. name
      .. " index=" .. tostring(ordinal)
      .. " hidden=" .. scalar(variant.hidden)
      .. " enabled=" .. scalar(variant.enabled)
      .. " declared_productivity=" .. scalar(variant.declared_allow_productivity)
      .. " effective_productivity=" .. scalar(variant.effective_allow_productivity)
      .. " maximum_productivity=" .. scalar(variant.effective_maximum_productivity)
      .. " inputs=" .. entry_line(variant.ingredients)
      .. " results=" .. entry_line(variant.results))
  end
end

local function collect_output_targets(fact, route, output_targets)
  for _, variant in ipairs(fact.variants or {}) do
    for _, result in ipairs(variant.results or {}) do
      local key = identity(result)
      local target = output_targets[key]
      if not target then target = {routes = {}}; output_targets[key] = target end
      target.routes[#target.routes + 1] = route
    end
  end
end

local function observe_hidden_output_consumers(output_targets, index)
  local count_by_output = {}
  for output in pairs(output_targets) do count_by_output[output] = 0 end
  for name, fact in pairs(index.facts or {}) do
    if fact.source_class == "hidden-internal" and fact.hidden == true and fact.enabled_without_research == false then
      for ordinal, variant in ipairs(fact.variants or {}) do
        if variant.hidden == true and variant.enabled == false then
          local matched = {}
          for _, ingredient in ipairs(variant.ingredients or {}) do
            local output = identity(ingredient)
            if output_targets[output] then matched[output] = true end
          end
          for output in pairs(matched) do
            count_by_output[output] = count_by_output[output] + 1
            log("[mir-f210-current-ba-final-observer] HIDDEN_OUTPUT_CONSUMER output=" .. output
              .. " routes=" .. names_line(output_targets[output].routes)
              .. " recipe=" .. name
              .. " index=" .. tostring(ordinal)
              .. " inputs=" .. entry_line(variant.ingredients)
              .. " results=" .. entry_line(variant.results))
          end
        end
      end
    end
  end
  local outputs = {}
  for output in pairs(output_targets) do outputs[#outputs + 1] = output end
  table.sort(outputs)
  for _, output in ipairs(outputs) do
    log("[mir-f210-current-ba-final-observer] HIDDEN_OUTPUT_SUMMARY output=" .. output
      .. " routes=" .. names_line(output_targets[output].routes)
      .. " count=" .. tostring(count_by_output[output]))
  end
end

log("[mir-f210-current-ba-final-observer] ACTIVE_MODS " .. active_mods_line())
compiler_context.with_active(compiler_context.new(), function()
  local index = recipe_facts.index_view()
  local input = relationships.view("input")
  if type(index) ~= "table" or type(index.facts) ~= "table" or type(input) ~= "table" then
    error("MIR F210 current Bob/Angel final observer requires finalized recipe and relationship indexes")
  end
  local output_targets, observed, missing = {}, 0, 0
  for _, candidate in ipairs(CANDIDATES) do
    local fact = recipe_facts.view(candidate.name)
    if type(fact) ~= "table" then
      missing = missing + 1
      log("[mir-f210-current-ba-final-observer] ROUTE recipe=" .. candidate.name
        .. " family=" .. candidate.family .. " shape=" .. candidate.shape .. " status=missing")
    else
      observed = observed + 1
      local generic, generic_reason = recipe_matching.material_route_is_acyclic(fact)
      local boundary, boundary_reason = recipe_matching.relevant_route_fingerprints(fact)
      local risk = recipe_risk_facts.view(candidate.name)
      log("[mir-f210-current-ba-final-observer] ROUTE recipe=" .. candidate.name
        .. " family=" .. candidate.family .. " shape=" .. candidate.shape .. " status=present"
        .. " generic=" .. scalar(generic) .. " reason=" .. scalar(generic_reason)
        .. " source=" .. scalar(fact.source_class) .. " hidden=" .. scalar(fact.hidden)
        .. " enabled_without_research=" .. scalar(fact.enabled_without_research)
        .. " declared_productivity=" .. scalar(fact.declared_allow_productivity)
        .. " effective_productivity=" .. scalar(fact.effective_allow_productivity)
        .. " maximum_productivity=" .. scalar(fact.effective_maximum_productivity)
        .. " risk=" .. scalar(risk and risk.risk_fingerprint)
        .. " graph=" .. scalar(boundary and boundary.return_graph_fingerprint)
        .. " bindings=" .. scalar(boundary and boundary.bindings_fingerprint)
        .. " identities=" .. scalar(boundary and boundary.reachable_identity_count)
        .. " recipes=" .. scalar(boundary and boundary.relevant_recipe_count)
        .. " producers=" .. scalar(boundary and boundary.direct_output_producer_count)
        .. " boundary_reason=" .. scalar(boundary_reason)
        .. " direct_producer_names=" .. direct_output_producers(fact, index))
      observe_variants(candidate.name, fact)
      observe_bindings(candidate.name, input)
      collect_output_targets(fact, candidate.name, output_targets)
    end
  end
  observe_hidden_output_consumers(output_targets, index)
  log("[mir-f210-current-ba-final-observer] DATA PASS read-only-finalized-contract-capture"
    .. " candidates=" .. tostring(#CANDIDATES)
    .. " observed=" .. tostring(observed)
    .. " missing=" .. tostring(missing))
end)

-- Independent, package-excluded denominator for the sixteen requested
-- material outputs. It reads finalized raw prototypes, never MIR selectors.
-- Prototype/producer observations do not establish acquisition or admission.
local M = {}
local SUBJECTS = {
  {"aluminium", "plate", {"bob-aluminium-plate", "angels-plate-aluminium"}},
  {"gold", "plate", {"bob-gold-plate", "angels-plate-gold"}},
  {"lead", "plate", {"bob-lead-plate", "angels-plate-lead"}},
  {"nickel", "plate", {"bob-nickel-plate", "angels-plate-nickel"}},
  {"platinum", "plate", {"bob-platinum-plate", "angels-plate-platinum"}},
  {"silver", "plate", {"bob-silver-plate", "angels-plate-silver"}},
  {"tin", "plate", {"bob-tin-plate", "angels-plate-tin"}},
  {"titanium", "plate", {"bob-titanium-plate", "angels-plate-titanium"}},
  {"copper-tungsten", "alloy", {"bob-copper-tungsten-alloy"}},
  {"zinc", "plate", {"bob-zinc-plate", "angels-plate-zinc"}},
  {"bronze", "alloy", {"bob-bronze-alloy", "angels-plate-bronze"}},
  {"brass", "alloy", {"bob-brass-alloy", "angels-plate-brass"}},
  {"gunmetal", "alloy", {"bob-gunmetal-alloy", "angels-plate-gunmetal"}},
  {"invar", "alloy", {"bob-invar-alloy", "angels-plate-invar"}},
  {"cobalt-steel", "alloy", {"bob-cobalt-steel-alloy", "angels-plate-cobalt-steel"}},
  {"nitinol", "alloy", {"bob-nitinol-alloy", "angels-plate-nitinol"}},
  -- Supplementary wire coverage never satisfies the original plate outcome.
  {"platinum", "wire", {"angels-wire-platinum"}}
}

local function positive(value)
  return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function ordered_keys(values, maximum, label)
  local keys = {}
  for key in pairs(values or {}) do
    if type(key) ~= "string" then error("Invalid " .. label .. " identity") end
    keys[#keys + 1] = key
    if #keys > maximum then error("Material inventory " .. label .. " budget exceeded") end
  end
  table.sort(keys)
  return keys
end

function M.collect(raw, limits)
  assert(type(raw) == "table", "Finalized raw prototypes required")
  limits = limits or {}
  local recipe_limit = limits.recipes or 10000
  local result_limit = limits.results or 60000
  assert(positive(recipe_limit) and recipe_limit == math.floor(recipe_limit)
    and recipe_limit <= 10000, "Invalid material inventory recipe budget")
  assert(positive(result_limit) and result_limit == math.floor(result_limit)
    and result_limit <= 60000, "Invalid material inventory result budget")
  local rows, by_item = {}, {}
  for _, subject in ipairs(SUBJECTS) do
    local row = {id = subject[1] .. "/" .. subject[2], family = subject[1], shape = subject[2],
      aliases = {}, present_items = {}, producers = {}}
    for _, name in ipairs(subject[3]) do
      row.aliases[#row.aliases + 1] = name
      by_item[name] = row
      local prototype = raw.item and raw.item[name]
      if prototype then
        row.present_items[#row.present_items + 1] = {name = name, hidden = prototype.hidden == true}
      end
    end
    rows[#rows + 1] = row
  end
  local visited_results = 0
  local recipe_names = ordered_keys(raw.recipe, recipe_limit, "recipe")
  for _, name in ipairs(recipe_names) do
    local recipe = raw.recipe[name]
    assert(type(recipe) == "table", "Invalid raw recipe")
    -- This observer is scoped to finalized F210 recipe prototypes. Legacy
    -- normal/expensive variants require a separately qualified adapter.
    assert(recipe.normal == nil and recipe.expensive == nil, "Legacy recipe variants need an inventory adapter")
    local matched = {}
    for _, result in ipairs(recipe.results or {}) do
      visited_results = visited_results + 1
      if visited_results > result_limit then error("Material inventory result budget exceeded") end
      assert(type(result) == "table", "Invalid raw recipe product")
      local item = result.name or result[1]
      local row = by_item[item]
      local amount = result.amount or result.amount_max or result.amount_min or result[2]
      local probability = result.independent_probability or result.probability
      if probability == nil then probability = 1 end
      if row and (result.type == nil or result.type == "item") and positive(amount)
        and positive(probability) and probability <= 1 then
        matched[row.id] = row
      end
    end
    for _, row in pairs(matched) do
      row.producers[#row.producers + 1] = {name = name, hidden = recipe.hidden == true,
        enabled_without_research = recipe.enabled ~= false,
        declared_allow_productivity = recipe.allow_productivity}
    end
  end
  for _, row in ipairs(rows) do
    row.status = #row.present_items == 0 and "prototype-absent"
      or (#row.producers == 0 and "no-observed-producer" or "observed")
  end
  return {schema = 1, kind = "MIRMaterialOutcomeInventoryV1", complete = true,
    phase = "finalized-raw-prototypes", rows = rows, recipe_count = #recipe_names,
    result_count = visited_results, acquisition_proved = false, admission_granted = false}
end

function M.route_gaps(inventory, observed_routes)
  assert(type(inventory) == "table" and inventory.complete == true, "Complete material inventory required")
  local seen = {}
  for _, name in ipairs(observed_routes or {}) do
    assert(type(name) == "string" and not seen[name], "Distinct observed recipe identities required")
    seen[name] = true
  end
  local missing = {}
  for _, row in ipairs(inventory.rows) do
    for _, producer in ipairs(row.producers) do
      if not seen[producer.name] then missing[#missing + 1] = {subject = row.id, recipe = producer.name} end
    end
  end
  return missing
end

local function token(value)
  assert(type(value) == "string" and #value > 0 and #value <= 256,
    "Bounded material inventory identity required")
  return (value:gsub("[^%w%-%._/]", function(character)
    return string.format("%%%02X", string.byte(character))
  end))
end

function M.lines(inventory, observed_routes)
  local prefix = "[mir-material-outcome-inventory] "
  local lines, gaps = {}, M.route_gaps(inventory, observed_routes)
  for _, row in ipairs(inventory.rows) do
    lines[#lines + 1] = prefix .. "SUBJECT id=" .. token(row.id) .. " status=" .. row.status
      .. " items=" .. #row.present_items .. " producers=" .. #row.producers
    for _, item in ipairs(row.present_items) do
      lines[#lines + 1] = prefix .. "ITEM subject=" .. token(row.id) .. " name=" .. token(item.name)
        .. " hidden=" .. tostring(item.hidden)
    end
    for _, producer in ipairs(row.producers) do
      lines[#lines + 1] = prefix .. "PRODUCER subject=" .. token(row.id) .. " recipe=" .. token(producer.name)
        .. " hidden=" .. tostring(producer.hidden) .. " enabled=" .. tostring(producer.enabled_without_research)
        .. " productivity=" .. (producer.declared_allow_productivity == nil and "unspecified"
          or tostring(producer.declared_allow_productivity))
    end
  end
  for _, gap in ipairs(gaps) do
    lines[#lines + 1] = prefix .. "GAP subject=" .. token(gap.subject) .. " recipe=" .. token(gap.recipe)
  end
  lines[#lines + 1] = prefix .. "PASS complete=true phase=finalized-raw-prototypes subjects=" .. #inventory.rows
    .. " recipes=" .. inventory.recipe_count .. " results=" .. inventory.result_count .. " gaps=" .. #gaps
    .. " acquisition=false admission=false"
  return lines
end

return M

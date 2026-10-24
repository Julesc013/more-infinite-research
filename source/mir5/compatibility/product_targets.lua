-- Bounded product-to-family selection for already-authored productivity
-- families.  This module only selects recipe targets; callers still own
-- family identities, effect construction, science, and prototype writes.
local M = {}
local target = require("platform.target")

local SEPARATOR = "\0"
local item_types = {
  "item", "tool", "mining-tool", "module", "ammo", "capsule", "gun", "armor", "repair-tool",
  "item-with-entity-data", "item-with-inventory", "item-with-label", "item-with-tags",
  "selection-tool", "copy-paste-tool", "blueprint", "blueprint-book", "deconstruction-item",
  "upgrade-item", "spidertron-remote", "rail-planner", "space-platform-starter-pack"
}

local function finite(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
end

local function dense_array(value, label)
  if type(value) ~= "table" then error("MIR product targets requires " .. label .. " to be an array", 3) end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      error("MIR product targets requires " .. label .. " to be a dense array", 3)
    end
    count = count + 1
  end
  if count ~= #value then error("MIR product targets requires " .. label .. " to be a dense array", 3) end
  return value
end

local function typed_identity(kind, name)
  if (kind ~= "item" and kind ~= "fluid") or type(name) ~= "string" or name == "" then return nil end
  return kind .. SEPARATOR .. name
end

local function product_identity(entry)
  if type(entry) ~= "table" then return nil end
  local name = entry.name
  if name == nil then name = entry[1] end
  local kind = entry.type or "item"
  local identity = typed_identity(kind, name)
  if not identity then return nil end
  return identity, kind, name
end

local function copy_target(target)
  return {
    family = target.family,
    recipe = target.recipe,
    product_type = target.product_type,
    product_name = target.product_name,
    weight = target.weight,
  }
end

local function copy_rule(rule, ordinal)
  if type(rule) ~= "table" or type(rule.family) ~= "string" or rule.family == "" then
    error("MIR product targets requires each binding to name a family", 3)
  end
  if not finite(rule.weight) or rule.weight <= 0 then
    error("MIR product targets requires a positive finite binding weight", 3)
  end
  dense_array(rule.products or {}, "binding products")
  local products, seen = {}, {}
  for _, product in ipairs(rule.products or {}) do
    local identity = product_identity(product)
    if not identity or seen[identity] then
      error("MIR product targets requires unique typed binding products", 3)
    end
    seen[identity] = true
    products[#products + 1] = identity
  end
  local function patterns(field)
    if rule[field] == nil then return nil end
    dense_array(rule[field], "binding " .. field)
    local out = {}
    for index, value in ipairs(rule[field]) do
      if type(value) ~= "string" or value == "" then
        error("MIR product targets requires string " .. field, 3)
      end
      local valid = pcall(string.find, "", value)
      if not valid then error("MIR product targets has an invalid " .. field .. " pattern", 3) end
      out[index] = value
    end
    return out
  end

  local item_patterns = patterns("item_patterns")
  local function names(field)
    local result = {}
    for _, name in ipairs(dense_array(rule[field] or {}, "binding " .. field)) do
      if type(name) ~= "string" or name == "" or result[name] then
        error("MIR product targets requires unique nonempty binding " .. field, 3)
      end
      result[name] = true
    end
    return result
  end
  local recipe_names, retained_owners = names("recipes"), names("retained_owners")
  local place_types = names("place_result_entity_types")
  local recipe_patterns = patterns("recipe_name_patterns")
  if #products == 0 and (item_patterns == nil or #item_patterns == 0)
    and next(recipe_names) == nil and next(place_types) == nil
    and (recipe_patterns == nil or #recipe_patterns == 0) then
    error("MIR product targets requires a binding product, recipe or pattern", 3)
  end

  for _, field in ipairs({"include_hidden", "include_recycling", "allow_shared_input_output",
    "reject_explicit_productivity_denial"}) do
    if rule[field] ~= nil and type(rule[field]) ~= "boolean" then
      error("MIR product targets requires boolean " .. field, 3)
    end
  end
  return {
    family = rule.family,
    weight = rule.weight,
    ordinal = ordinal,
    products = products,
    item_patterns = item_patterns,
    recipes = recipe_names,
    recipe_name_patterns = recipe_patterns,
    retained_owners = retained_owners,
    retained_owned_recipes = {},
    place_result_entity_types = place_types,
    exclude_recipe_patterns = patterns("exclude_recipe_patterns"),
    exclude_ingredient_patterns = patterns("exclude_ingredient_patterns"),
    include_hidden = rule.include_hidden == true,
    include_recycling = rule.include_recycling == true,
    allow_shared_input_output = rule.allow_shared_input_output == true,
    reject_explicit_productivity_denial = rule.reject_explicit_productivity_denial == true,
  }
end

-- Index the selected authored bindings before inspecting recipes. The returned
-- context is phase-local: callers must prepare it again after a foreign data
-- stage can replace recipes or binding declarations.
function M.prepare(bindings, options)
  dense_array(bindings, "bindings")
  options = options or {}
  if type(options) ~= "table" then error("MIR product targets has invalid options", 2) end
  local probability_field = options.probability_field
  if probability_field == nil then probability_field = target.recipe_probability end
  if probability_field == nil then probability_field = "independent_probability" end
  local productivity_ignores_stats = options.productivity_ignores_stats
  if productivity_ignores_stats == nil then productivity_ignores_stats = target.productivity_ignores_stats == true end
  if (productivity_ignores_stats ~= nil
    and type(productivity_ignores_stats) ~= "boolean")
    or (probability_field ~= "probability" and probability_field ~= "independent_probability") then
    error("MIR product targets has invalid options", 2)
  end
  local interested, rules, by_recipe = {}, {}, {}
  local pattern_rules, recipe_pattern_rules = {}, {}
  for ordinal, binding in ipairs(bindings) do
    local rule = copy_rule(binding, ordinal)
    rules[#rules + 1] = rule
    if (rule.item_patterns and #rule.item_patterns > 0) or next(rule.place_result_entity_types) then
      pattern_rules[#pattern_rules + 1] = rule
    end
    if rule.recipe_name_patterns and #rule.recipe_name_patterns > 0 then
      recipe_pattern_rules[#recipe_pattern_rules + 1] = rule
    end
    for name in pairs(rule.recipes) do
      if by_recipe[name] == nil then by_recipe[name] = {} end
      by_recipe[name][#by_recipe[name] + 1] = rule
    end
  end

  -- Preserve only the named native owners relevant to these declarations.
  -- No technology enumeration, unlock/science check or foreign graph walk.
  local owners, owner_count = {}, 0
  for _, rule in ipairs(rules) do
    for owner_name in pairs(rule.retained_owners) do
      if owners[owner_name] == nil then
        if type(options.raw) ~= "table" then error("MIR retained owner targets requires native prototypes", 2) end
        local owner = options.raw.technology and options.raw.technology[owner_name]
        local recipes = {}
        if type(owner) == "table" and type(owner.effects) == "table" then
          for _, effect in ipairs(owner.effects) do
            if type(effect) == "table" and effect.type == "change-recipe-productivity"
              and type(effect.recipe) == "string" and finite(effect.change) and effect.change > 0 then
              recipes[effect.recipe] = true
            end
          end
        end
        owners[owner_name], owner_count = recipes, owner_count + 1
      end
      for recipe_name in pairs(owners[owner_name]) do rule.retained_owned_recipes[recipe_name] = true end
    end
  end

  -- Resolve the retained item patterns/place-result types once into the same
  -- typed product index. Only named entity classes are inspected, never the
  -- whole prototype world or a recipe pass for every family.
  local item_count, pattern_tests, entity_count = 0, 0, 0
  if #pattern_rules > 0 then
    if type(options.raw) ~= "table" then error("MIR item pattern targets requires native prototypes", 2) end
    local entity_types, entities = {}, {}
    for _, rule in ipairs(pattern_rules) do
      for kind in pairs(rule.place_result_entity_types) do entity_types[kind] = true end
    end
    for kind in pairs(entity_types) do
      for name in pairs(options.raw[kind] or {}) do
        entity_count = entity_count + 1
        if entities[name] and entities[name] ~= kind then
          error("MIR product target entity has multiple types: " .. tostring(name), 2)
        end
        entities[name] = kind
      end
    end
    local seen = {}
    for _, rule in ipairs(pattern_rules) do
      seen[rule.ordinal] = {}
      for _, identity in ipairs(rule.products) do seen[rule.ordinal][identity] = true end
    end
    for _, kind in ipairs(item_types) do
      for name, prototype in pairs(options.raw[kind] or {}) do
        item_count = item_count + 1
        if type(name) == "string" and name ~= "" and type(prototype) == "table" then
          local identity = typed_identity("item", name)
          for _, rule in ipairs(pattern_rules) do
            if not seen[rule.ordinal][identity] then
              local matches = type(prototype.place_result) == "string"
                and rule.place_result_entity_types[entities[prototype.place_result]] == true
              for _, pattern in ipairs(rule.item_patterns or {}) do
                if matches then break end
                pattern_tests = pattern_tests + 1
                if string.find(name, pattern) then matches = true; break end
              end
              if matches then
                rule.products[#rule.products + 1] = identity
                seen[rule.ordinal][identity] = true
              end
            end
          end
        end
      end
    end
  end
  for _, rule in ipairs(rules) do
    for _, identity in ipairs(rule.products) do
      local rows = interested[identity]
      if rows == nil then rows = {}; interested[identity] = rows end
      rows[#rows + 1] = rule
    end
  end
  return {
    schema = 1,
    interested = interested,
    rules = rules,
    by_recipe = by_recipe,
    recipe_pattern_rules = recipe_pattern_rules,
    owners = owner_count,
    items = item_count,
    entities = entity_count,
    pattern_tests = pattern_tests,
    probability_field = probability_field,
    productivity_ignores_stats = productivity_ignores_stats == true,
  }
end

local function entries(definition, field)
  local plural = definition[field]
  if plural ~= nil then
    if type(plural) ~= "table" then return nil end
    local ok = pcall(dense_array, plural, "recipe " .. field)
    if not ok then return nil end
    return plural
  end
  local singular = field == "results" and definition.result or definition.ingredient
  if singular == nil then return {} end
  if type(singular) ~= "string" or singular == "" then return nil end
  return {{name = singular, type = "item", amount = field == "results"
    and (definition.result_count == nil and 1 or definition.result_count)
    or (definition.ingredient_amount == nil and 1 or definition.ingredient_amount)}}
end

local function variants(recipe)
  local normal, expensive = recipe.normal, recipe.expensive
  if normal == nil and expensive == nil then return {{definition = recipe}} end
  local out = {}
  for _, field in ipairs({"normal", "expensive"}) do
    local definition = recipe[field]
    if definition ~= nil then
      if type(definition) ~= "table" then return nil end
      out[#out + 1] = {definition = definition}
    end
  end
  return out
end

local function inherited(recipe, definition, field)
  if definition[field] ~= nil then return definition[field] end
  return recipe[field]
end

local function recipe_categories(recipe, definition)
  local categories = inherited(recipe, definition, "categories")
  if categories ~= nil then
    if type(categories) ~= "table" then return nil end
    local ok = pcall(dense_array, categories, "recipe categories")
    if not ok then return nil end
    local out = {}
    for _, category in ipairs(categories) do
      if type(category) ~= "string" or category == "" then return nil end
      out[category] = true
    end
    return out
  end
  local category = inherited(recipe, definition, "category")
  if category == nil then return {crafting = true} end
  if type(category) ~= "string" or category == "" then return nil end
  return {[category] = true}
end

local function positive_product(entry, productivity_ignores_stats, probability_field)
  local identity, kind = product_identity(entry)
  if not identity then return nil end
  local amount = entry.amount
  if amount == nil then amount = entry[2] end
  local maximum
  if amount ~= nil then
    if not finite(amount) or amount < 0 then return nil end
    maximum = amount
  else
    local minimum, upper = entry.amount_min, entry.amount_max
    if not finite(minimum) or not finite(upper) or minimum < 0 or upper < minimum then return nil end
    maximum = upper
  end
  local other_probability = probability_field == "probability" and "independent_probability" or "probability"
  if entry[other_probability] ~= nil then return nil end
  local probability = entry[probability_field]
  if probability == nil then probability = 1 end
  if not finite(probability) or probability <= 0 or probability > 1 then return nil end
  local shared = entry.shared_probability
  if shared ~= nil then
    if type(shared) ~= "table" or not finite(shared.min) or not finite(shared.max)
      or shared.min < 0 or shared.max > 1 or shared.min >= shared.max then return nil end
  end
  local ignored = entry.ignored_by_productivity
  if ignored == nil and productivity_ignores_stats then ignored = entry.ignored_by_stats end
  if ignored == nil then ignored = 0 end
  if not finite(ignored) or ignored < 0 then return nil end
  local extra = entry.extra_count_fraction
  if extra == nil then extra = 0 end
  if not finite(extra) or extra < 0 or extra > 1 then return nil end
  if entry.catalyst_amount ~= nil and (not finite(entry.catalyst_amount) or entry.catalyst_amount < 0) then
    return nil
  end
  -- An excluded base amount does not authorize a fractional extra roll. This
  -- is the existing local-yield boundary, not a return-route proof.
  local productive = maximum - ignored > 0
    or (kind == "item" and ignored == 0 and extra > 0)
  if not productive then return nil end
  return identity, kind, entry.name or entry[1]
end

local function name_matches(name, patterns)
  for _, pattern in ipairs(patterns or {}) do
    if string.find(name, pattern) then return true end
  end
  return false
end

local function recipe_blocked(recipe_name, summary, rule)
  if rule.retained_owned_recipes[recipe_name] then return true end
  if name_matches(recipe_name, rule.exclude_recipe_patterns) then return true end
  if summary.hidden and not rule.include_hidden then return true end
  if summary.recycling and not rule.include_recycling then return true end
  if summary.shared_productive and not rule.allow_shared_input_output then return true end
  if rule.reject_explicit_productivity_denial and summary.productivity_denied then return true end
  for ingredient_name in pairs(summary.ingredient_names) do
    if name_matches(ingredient_name, rule.exclude_ingredient_patterns) then return true end
  end
  return false
end

local function inspect_recipe(recipe, context, work)
  if type(recipe) ~= "table" or recipe.parameter == true then return nil end
  local rows = variants(recipe)
  if rows == nil or #rows == 0 then return nil end
  local summary = {ingredient_names = {}, matches = {}, hidden = false, recycling = false,
    shared_productive = false, productivity_denied = false}
  for _, row in ipairs(rows) do
    local definition = row.definition
    local ingredients, results = entries(definition, "ingredients"), entries(definition, "results")
    if ingredients == nil or results == nil then return nil end
    local categories = recipe_categories(recipe, definition)
    if categories == nil then return nil end
    if inherited(recipe, definition, "hidden") == true then summary.hidden = true end
    if categories.recycling then summary.recycling = true end
    if inherited(recipe, definition, "allow_productivity") == false
      or inherited(recipe, definition, "maximum_productivity") == 0 then
      summary.productivity_denied = true
    end
    local inputs = {}
    for _, ingredient in ipairs(ingredients) do
      local identity, _, name = product_identity(ingredient)
      if not identity then return nil end
      inputs[identity], summary.ingredient_names[name] = true, true
      work.ingredients = work.ingredients + 1
    end
    for _, product in ipairs(results) do
      work.products = work.products + 1
      local identity, kind, name = positive_product(product, context.productivity_ignores_stats, context.probability_field)
      if identity then
        if not summary.product_type then summary.product_type, summary.product_name = kind, name end
        if inputs[identity] then summary.shared_productive = true end
        local interested = context.interested[identity]
        if interested then
          for _, rule in ipairs(interested) do
            work.matches = work.matches + 1
            if summary.matches[rule.ordinal] == nil then
              summary.matches[rule.ordinal] = {rule = rule, product_type = kind, product_name = name}
            end
          end
        end
      elseif product_identity(product) == nil then
        return nil
      end
    end
  end
  return summary
end

-- Visit each recipe and product entry once. `recipes` is the current
-- data-stage recipe map; it is never changed. `context` must be the result of
-- prepare() for this same data-stage phase.
function M.collect(recipes, context)
  if type(recipes) ~= "table" then error("MIR product targets requires a recipe map", 2) end
  if type(context) ~= "table" or context.schema ~= 1 or type(context.interested) ~= "table" then
    error("MIR product targets requires a prepared context", 2)
  end
  local work = {recipes = 0, products = 0, ingredients = 0, matches = 0,
    items = context.items, pattern_tests = context.pattern_tests, recipe_pattern_tests = 0,
    owners = context.owners, entities = context.entities}
  local targets, by_family = {}, {}
  for recipe_name, recipe in pairs(recipes) do
    if type(recipe_name) == "string" and recipe_name ~= "" then
      work.recipes = work.recipes + 1
      local summary = inspect_recipe(recipe, context, work)
      if summary then
        -- Exact alternatives use a direct lookup. The one retained breeding
        -- name-pattern contract shares this same recipe pass, after local yield
        -- inspection; a name alone never admits a zero/ignored output.
        if summary.product_type then
          local function match_rule(rule)
            work.matches = work.matches + 1
            if not summary.matches[rule.ordinal] then
              summary.matches[rule.ordinal] = {rule=rule,
                product_type=summary.product_type, product_name=summary.product_name}
            end
          end
          for _, rule in ipairs(context.by_recipe[recipe_name] or {}) do match_rule(rule) end
          for _, rule in ipairs(context.recipe_pattern_rules) do
            for _, pattern in ipairs(rule.recipe_name_patterns) do
              work.recipe_pattern_tests = work.recipe_pattern_tests + 1
              if string.find(recipe_name, pattern) then match_rule(rule); break end
            end
          end
        end
        local admitted = {}
        for _, match in pairs(summary.matches) do
          local rule = match.rule
          local prior = admitted[rule.family]
          -- Published groups filter their own exclusions before claiming a
          -- recipe. A blocked early group must not suppress a later valid one.
          if not recipe_blocked(recipe_name, summary, rule)
            and (prior == nil or rule.ordinal < prior.rule.ordinal) then
            admitted[rule.family] = match
          end
        end
        for family, match in pairs(admitted) do
          local rule = match.rule
          local target = {family = family, recipe = recipe_name, product_type = match.product_type,
            product_name = match.product_name, weight = rule.weight}
          targets[#targets + 1] = target
          local rows = by_family[family]
          if rows == nil then rows = {}; by_family[family] = rows end
          rows[#rows + 1] = copy_target(target)
        end
      end
    end
  end
  table.sort(targets, function(left, right)
    if left.family ~= right.family then return left.family < right.family end
    if left.recipe ~= right.recipe then return left.recipe < right.recipe end
    if left.product_type ~= right.product_type then return left.product_type < right.product_type end
    return left.product_name < right.product_name
  end)
  for _, rows in pairs(by_family) do
    table.sort(rows, function(left, right)
      if left.recipe ~= right.recipe then return left.recipe < right.recipe end
      if left.product_type ~= right.product_type then return left.product_type < right.product_type end
      return left.product_name < right.product_name
    end)
  end
  return {schema = 1, targets = targets, by_family = by_family, work = work}
end

return M

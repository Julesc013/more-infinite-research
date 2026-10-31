-- One diagnostic window per init/config/load activation; exclude from acceptance timing.
-- Native entities, research, settings and saved storage are read-only here.
local WINDOW = 600
local MAX_SURFACES = 32
local SAMPLE_PER_SURFACE = 256
local MAX_MODS = 128
local MAX_REPORT_BYTES = 65536
local PREFIX = "[MIR5_LARGE_FACTORY_ACTIVITY] "
local TYPES = {"assembling-machine", "furnace", "mining-drill", "lab", "inserter",
  "transport-belt", "locomotive", "roboport", "agricultural-tower"}
local ITEMS = {"iron-plate", "copper-plate", "steel-plate", "stone-brick", "plastic-bar", "sulfur",
  "electronic-circuit", "advanced-circuit", "processing-unit", "automation-science-pack",
  "logistic-science-pack", "chemical-science-pack", "production-science-pack",
  "utility-science-pack", "space-science-pack"}
local first_tick, first_rows, sampled, selected_surfaces, selected_force, metadata

local function fail(message) error("[mir5-large-factory-activity] " .. message) end
local function counter(value)
  if type(value) ~= "number" or value ~= value or value < 0 or value > 9007199254740991
      or value % 1 ~= 0 then fail("native counter is outside the exact nonnegative integer bound") end
  return value
end
local function emit(kind, report)
  local text = helpers.table_to_json(report)
  if type(text) ~= "string" or #text > MAX_REPORT_BYTES then fail("report byte bound exceeded") end
  log(PREFIX .. kind .. " " .. text)
end
local function surfaces()
  local values, seen = {}, {}
  for _, surface in pairs(game.surfaces) do
    if surface.valid and not seen[surface.index] then
      seen[surface.index] = true
      values[#values + 1] = surface
      if #values > MAX_SURFACES then fail("surface bound exceeded; declare a different input") end
    end
  end
  table.sort(values, function(a, b) return a.index < b.index end)
  return values
end
local function snapshot(surface)
  local row = {index = surface.index, name = string.sub(surface.name, 1, 128),
    name_truncated = #surface.name > 128, entity_counts = {}, normal_item_inputs = {}}
  for _, kind in ipairs(TYPES) do
    row.entity_counts[kind] = counter(surface.count_entities_filtered{force = selected_force, type = kind})
  end
  local stats = selected_force.get_item_production_statistics(surface)
  for _, name in ipairs(ITEMS) do
    if prototypes.item[name] then row.normal_item_inputs[name] = counter(stats.get_input_count(name)) end
  end
  return row
end
local function begin(tick)
  local base = script.active_mods.base
  if base ~= "2.0.77" and base ~= "2.1.23" then fail("requires pinned 2.0.77 or 2.1.23") end
  selected_force = game.forces.player
  if not selected_force or not selected_force.valid then fail("player force is unavailable") end
  local mods = {}
  for name, version in pairs(script.active_mods) do
    if type(name) ~= "string" or #name > 100 or type(version) ~= "string" or #version > 32 then
      fail("active mod identity bound exceeded")
    end
    mods[#mods + 1] = {name = name, version = version}
    if #mods > MAX_MODS then fail("active mod bound exceeded") end
  end
  table.sort(mods, function(a, b) return a.name < b.name end)
  metadata = {base_version = base, mir_version = script.active_mods["more-infinite-research"] or false,
    mods = mods, force_index = selected_force.index, force_name = selected_force.name}
  selected_surfaces, first_rows, sampled = surfaces(), {}, {}
  for _, surface in ipairs(selected_surfaces) do
    first_rows[#first_rows + 1] = snapshot(surface)
    local found = surface.find_entities_filtered{force = selected_force,
      type = {"assembling-machine", "furnace"}, limit = SAMPLE_PER_SURFACE}
    if #found > SAMPLE_PER_SURFACE then fail("native machine sample exceeds its declared limit") end
    for _, entity in ipairs(found) do
      sampled[#sampled + 1] = {entity = entity, initial = counter(entity.products_finished)}
    end
  end
  first_tick = tick
  emit("START", {schema = 1, first_tick = tick, window_ticks = WINDOW,
    surfaces = #selected_surfaces, sampled_machines = #sampled, performance_acceptance = false})
end
local function finish(tick)
  if not selected_force.valid then fail("player force invalidated during the window") end
  local final_rows, progress, invalid, decreases = {}, 0, 0, 0
  local produced, production_decreases = 0, 0
  local removed = 0
  for index, surface in ipairs(selected_surfaces) do
    if not surface.valid then
      removed = removed + 1
      final_rows[#final_rows + 1] = {index = first_rows[index].index, invalidated = true}
    else
      local row = snapshot(surface)
      row.normal_item_input_deltas = {}
      for name, before in pairs(first_rows[index].normal_item_inputs) do
        local after = row.normal_item_inputs[name]
        if after == nil then fail("sampled native item became unavailable") end
        local delta = after - before
        row.normal_item_input_deltas[name] = delta
        if delta > 0 then produced = counter(produced + delta) end
        if delta < 0 then production_decreases = production_decreases + 1 end
      end
      final_rows[#final_rows + 1] = row
    end
  end
  local completed = 0
  for _, sample in ipairs(sampled) do
    if not sample.entity.valid then invalid = invalid + 1
    else
      local delta = counter(sample.entity.products_finished) - sample.initial
      if delta > 0 then progress = progress + 1; completed = completed + delta end
      if delta < 0 then decreases = decreases + 1 end
    end
  end
  local report = {schema = 1, kind = "MIRLargeFactoryActivityDiagnosticV1", metadata = metadata,
    first_tick = first_tick, final_tick = tick, observed_ticks = tick - first_tick,
    initial = first_rows, final = final_rows, surface_count_after = #surfaces(),
    invalidated_surfaces = removed, sampled_machines = #sampled, sampled_machines_with_progress = progress,
    sampled_products_finished_delta = completed, invalidated_sampled_machines = invalid,
    sampled_product_counter_decreases = decreases, positive_normal_item_input_delta = produced,
    normal_item_counter_decreases = production_decreases,
    activity_observed = progress > 0 or produced > 0, large_factory_qualified = false,
    performance_acceptance = false, release_qualification = false,
    limitations = {"One diagnostic 600-tick window per init/config/load activation; exclude from acceptance timing.",
      "Entity counts cover the player force on selected initial surfaces; they do not prove activity.",
      "Machine samples are bounded native-order subsets, not random samples or a whole-factory estimate.",
      "Production counters cover the 15 named normal-quality items; other activity may be unobserved.",
      "Counter decreases are reported, not reinterpreted as completed work. No native state preservation verdict."}}
  script.on_event(defines.events.on_tick, nil)
  first_tick, first_rows, sampled, selected_surfaces, selected_force, metadata = nil, nil, nil, nil, nil, nil
  emit("COMPLETE", report)
end
local function tick(event)
  if first_tick == nil then begin(event.tick)
  elseif event.tick == first_tick + WINDOW then finish(event.tick)
  elseif event.tick > first_tick + WINDOW then fail("observation window skipped its fixed endpoint") end
end
local function arm()
  first_tick, first_rows, sampled, selected_surfaces, selected_force, metadata = nil, nil, nil, nil, nil, nil
  script.on_event(defines.events.on_tick, tick)
end
script.on_init(arm)
script.on_configuration_changed(arm)
-- Reconnect only local state/registration. Never access game or storage here.
script.on_load(arm)

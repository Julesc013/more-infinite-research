-- Private VEH-02 capability probe.  It is deliberately not a MIR runtime
-- service: it asks whether the engine gives each native vehicle type a safe,
-- paired fuel-economy mapping before any product admission is considered.
local car_service = require("optional_runtime_services")

local factor = 0.8
local assertions = 0
local function check(value, message)
  assert(value, message)
  assertions = assertions + 1
end

local function rounded(value)
  if type(value) ~= "number" then return value end
  return math.floor(value * 1000000 + 0.5) / 1000000
end

local function error_text(value)
  if value == nil then return nil end
  return tostring(value):gsub("[\r\n]", " ")
end

local function fuel_energy(entity)
  local ok_burner, burner = pcall(function() return entity.burner end)
  if not ok_burner or not burner then return nil, "no-burner" end
  local ok_inventory, inventory = pcall(function() return entity.get_fuel_inventory() end)
  if not ok_inventory or not inventory then return nil, "no-fuel-inventory" end
  local ok_coal, coal = pcall(function() return inventory.get_item_count("coal") end)
  local ok_remaining, remaining = pcall(function() return burner.remaining_burning_fuel end)
  if not ok_coal or not ok_remaining then return nil, "unreadable-burner-state" end
  return coal * 4000000 + remaining
end

local function setter_probe(entity)
  local row = { attempted = true, factor = factor }
  local ok_before, before_or_error = pcall(function()
    return { consumption = entity.consumption_modifier, effectivity = entity.effectivity_modifier }
  end)
  if not ok_before then
    row.supported = false
    row.reason = "modifiers-unreadable: " .. error_text(before_or_error)
    return row
  end
  row.before = { consumption = rounded(before_or_error.consumption), effectivity = rounded(before_or_error.effectivity) }
  local expected_consumption = before_or_error.consumption * factor
  local expected_effectivity = before_or_error.effectivity / factor
  local ok_consumption, consumption_error = pcall(function()
    entity.consumption_modifier = expected_consumption
  end)
  local ok_effectivity, effectivity_error = pcall(function()
    entity.effectivity_modifier = expected_effectivity
  end)
  local observed_consumption, observed_effectivity
  local ok_observed, observed_error = pcall(function()
    observed_consumption = entity.consumption_modifier
    observed_effectivity = entity.effectivity_modifier
  end)
  row.write = {
    consumption = ok_consumption,
    effectivity = ok_effectivity,
    observed = ok_observed
  }
  if not ok_consumption then row.write.consumption_error = error_text(consumption_error) end
  if not ok_effectivity then row.write.effectivity_error = error_text(effectivity_error) end
  if not ok_observed then row.write.observed_error = error_text(observed_error) end
  row.after = { consumption = rounded(observed_consumption), effectivity = rounded(observed_effectivity) }
  row.supported = ok_consumption and ok_effectivity and ok_observed
    and math.abs(observed_consumption - expected_consumption) < 0.00001
    and math.abs(observed_effectivity - expected_effectivity) < 0.00001
  if not row.supported and not row.reason then row.reason = "setter-write-not-retained" end
  return row
end

local function restore_setters(entity, row)
  if not row.before then return false, "no-setter-baseline" end
  local ok, err = pcall(function()
    entity.consumption_modifier = row.before.consumption
    entity.effectivity_modifier = row.before.effectivity
  end)
  if not ok then return false, error_text(err) end
  local restored = math.abs(entity.consumption_modifier - row.before.consumption) < 0.00001
    and math.abs(entity.effectivity_modifier - row.before.effectivity) < 0.00001
  if restored then return true, nil end
  return false, "setter-restore-not-retained"
end

local function apply_setters(entity, row)
  if not row.before or not row.supported then return false, "setter-probe-did-not-pass" end
  local ok, err = pcall(function()
    entity.consumption_modifier = row.before.consumption * factor
    entity.effectivity_modifier = row.before.effectivity / factor
  end)
  if not ok then return false, error_text(err) end
  local retained = math.abs(entity.consumption_modifier - row.before.consumption * factor) < 0.00001
    and math.abs(entity.effectivity_modifier - row.before.effectivity / factor) < 0.00001
  if retained then return true, nil end
  return false, "applied-setters-not-retained"
end

local function distance(position, origin)
  local x = position.x - origin.x
  local y = position.y - origin.y
  return math.sqrt(x * x + y * y)
end

local function fuel_profile(entity)
  local row = { categories = {} }
  local ok_burner, burner = pcall(function() return entity.prototype.burner_prototype end)
  if not ok_burner or not burner then
    row.reason = "no-burner-prototype"
    return row
  end
  local ok_categories, categories_or_error = pcall(function() return burner.fuel_categories end)
  if not ok_categories or not categories_or_error then
    row.reason = "burner-fuel-categories-unreadable: " .. error_text(categories_or_error)
    return row
  end
  for name in pairs(categories_or_error) do row.categories[#row.categories + 1] = name end
  table.sort(row.categories)
  row.coal_category_accepted = false
  for _, name in ipairs(row.categories) do if name == "chemical" then row.coal_category_accepted = true end end
  local ok_insert, inserted_or_error = pcall(function() return entity.insert { name = "coal", count = 100 } end)
  row.coal_inserted = ok_insert and inserted_or_error and inserted_or_error > 0
  if not row.coal_inserted then
    row.reason = ok_insert and "coal-not-accepted-by-vehicle-fuel-inventory" or ("coal-insert-failed: " .. error_text(inserted_or_error))
  end
  return row
end

local function start_manual_work(surface, entity, origin)
  local row = { attempted = true, origin = { x = origin.x, y = origin.y }, input = "normal-riding-state" }
  local ok, err = pcall(function()
    local driver = surface.create_entity { name = "character", position = origin, force = "player" }
    entity.set_driver(driver)
    entity.riding_state = {
      acceleration = defines.riding.acceleration.accelerating,
      direction = defines.riding.direction.straight
    }
  end)
  row.started = ok
  if not ok then row.reason = "normal-driving-input-unavailable: " .. error_text(err) end
  return row
end

local function build_track(surface, x)
  local rail_name = prototypes.entity["straight-rail"] and "straight-rail" or (prototypes.entity["rail"] and "rail" or nil)
  local built = 0
  if not rail_name then return { built = 0, reason = "no-installed-straight-rail-prototype" } end
  for y = -180, 180, 2 do
    local rail = surface.create_entity {
      name = rail_name,
      position = { x = x, y = y },
      direction = defines.direction.north,
      force = "player"
    }
    if rail then built = built + 1 end
  end
  return { name = rail_name, built = built }
end

local function make_vehicle(surface, kind, x, track)
  local entity = surface.create_entity {
    name = kind == "locomotive" and "locomotive" or (kind == "spider-vehicle" and "spidertron" or "car"),
    position = { x = x, y = 0 },
    direction = defines.direction.north,
    force = "player"
  }
  local row = { kind = kind, entity_created = entity ~= nil, track = track }
  if not entity then return nil, row end
  row.fuel = fuel_profile(entity)
  row.setters = setter_probe(entity)
  if row.setters.before then
    row.setter_probe_restored, row.setter_probe_restore_reason = restore_setters(entity, row.setters)
  else
    row.setter_probe_restored = nil
    row.setter_probe_restore_reason = "not-applicable-without-readable-setter-baseline"
  end
  return { entity = entity, row = row }, row
end

local function set_work_unattempted(pair, reason)
  pair.control.row.work = { attempted = false, reason = reason }
  pair.economy.row.work = { attempted = false, reason = reason }
end

local function capture_motion(state, tick)
  for _, pair in pairs(state.pairs) do
    if not pair.unavailable and pair.control.row.work and pair.control.row.work.attempted and pair.economy.row.work and pair.economy.row.work.attempted then
      for _, side in ipairs({ pair.control, pair.economy }) do
        local ok_speed, speed_or_error = pcall(function() return side.entity.speed end)
        local sample = { tick = tick, distance = rounded(distance(side.entity.position, side.row.work.origin)) }
        if ok_speed then sample.speed = rounded(speed_or_error) else sample.speed_error = error_text(speed_or_error) end
        side.row.work.samples = side.row.work.samples or {}
        side.row.work.samples[#side.row.work.samples + 1] = sample
      end
    end
  end
end

local function matched_motion_samples(control, economy)
  local control_samples = control.work and control.work.samples or {}
  local economy_samples = economy.work and economy.work.samples or {}
  local row = { sample_count = #control_samples, speed_matched = false, acceleration_matched = false }
  if #control_samples < 2 or #control_samples ~= #economy_samples then
    row.reason = "insufficient-paired-motion-samples"
    return row
  end
  local speed_matched, acceleration_matched = true, true
  local accelerations = { control = {}, economy = {} }
  for index = 1, #control_samples do
    local c, e = control_samples[index], economy_samples[index]
    if c.tick ~= e.tick or type(c.speed) ~= "number" or type(e.speed) ~= "number" or math.abs(c.speed - e.speed) > 0.0001 then speed_matched = false end
    if index > 1 and type(c.speed) == "number" and type(e.speed) == "number" then
      local previous_c, previous_e = control_samples[index - 1], economy_samples[index - 1]
      local ticks = c.tick - previous_c.tick
      if ticks <= 0 or previous_c.tick ~= previous_e.tick or type(previous_c.speed) ~= "number" or type(previous_e.speed) ~= "number" then
        acceleration_matched = false
      else
        local control_acceleration = (c.speed - previous_c.speed) / ticks
        local economy_acceleration = (e.speed - previous_e.speed) / ticks
        accelerations.control[#accelerations.control + 1] = rounded(control_acceleration)
        accelerations.economy[#accelerations.economy + 1] = rounded(economy_acceleration)
        if math.abs(control_acceleration - economy_acceleration) > 0.0001 then acceleration_matched = false end
      end
    end
  end
  row.speed_matched = speed_matched
  row.acceleration_matched = acceleration_matched
  row.acceleration_samples = accelerations
  if not speed_matched or not acceleration_matched then row.reason = "paired-normal-motion-speed-or-acceleration-differed" end
  return row
end

local function complete_pair(kind, control, economy, finish_mapping)
  local row = {
    kind = kind,
    setter_support = economy.row.setters.supported,
    control = control.row,
    economy = economy.row
  }
  local c, e = control.row, economy.row
  if not (c.work and c.work.attempted and e.work and e.work.attempted) then
    row.work = { attempted = false, reason = (c.work and c.work.reason) or (e.work and e.work.reason) or "paired-normal-work-not-started", measurable = false, ratio_matches = false }
    if e.mapping_applied then
      local restored, restore_reason = finish_mapping(economy.entity, e.setters)
      row.economy.setter_restored = restored
      if restore_reason then row.economy.setter_restore_reason = restore_reason end
    else
      row.economy.setter_restored = nil
      row.economy.setter_restore_reason = "not-applicable-without-an-applied-economy-mapping"
    end
    row.engine_native_mapping = false
    row.decision = "not-admitted-by-this-probe"
    return row
  end
  for _, side in ipairs({ control, economy }) do
    side.row.end_energy, side.row.end_energy_reason = fuel_energy(side.entity)
    side.row.distance = rounded(distance(side.entity.position, side.row.work.origin))
    side.row.fuel_used = side.row.start_energy and side.row.end_energy and rounded(side.row.start_energy - side.row.end_energy) or nil
  end
  local same_distance = c.distance and e.distance and math.abs(c.distance - e.distance) <= 0.05
  local motion = matched_motion_samples(c, e)
  local measurable = c.fuel_used and e.fuel_used and c.fuel_used > 0 and e.fuel_used > 0
    and c.distance and e.distance and c.distance > 0.1 and e.distance > 0.1 and same_distance and motion.speed_matched and motion.acceleration_matched
  row.work = {
    attempted = true,
    normal_input = c.work.input,
    control_distance = c.distance,
    economy_distance = e.distance,
    control_fuel_used = c.fuel_used,
    economy_fuel_used = e.fuel_used,
    equal_distance = same_distance,
    motion = motion,
    measurable = measurable
  }
  if measurable then
    row.work.fuel_ratio = rounded(e.fuel_used / c.fuel_used)
    row.work.expected_ratio = factor
    row.work.ratio_matches = math.abs(row.work.fuel_ratio - factor) <= 0.01
  else
    row.work.ratio_matches = false
    row.work.reason = motion.reason or "paired-normal-work-did-not-produce-equal-distance-positive-fuel-consumption"
  end
  local restored, restore_reason = finish_mapping(economy.entity, e.setters)
  row.economy.setter_restored = restored
  if restore_reason then row.economy.setter_restore_reason = restore_reason end
  -- Setter writability alone is intentionally not treated as an economy mapping.
  row.engine_native_mapping = row.setter_support and e.mapping_applied and row.work.measurable and row.work.ratio_matches
  row.decision = row.engine_native_mapping and "measured-native-mapping" or "not-admitted-by-this-probe"
  return row
end

local function initialize_probe(event)
  if storage.vehicle_economy_probe then return end
  storage.vehicle_economy_probe = { tick = event.tick, phase = "running" }
  local surface = game.create_surface("mir-vehicle-economy-capability", {
    width = 512,
    height = 512,
    autoplace_settings = { entity = { treat_missing_as_default = false }, decorative = { treat_missing_as_default = false } }
  })
  surface.request_to_generate_chunks({ 0, 0 }, 8)
  surface.force_generate_chunk_requests()
  local tiles = {}
  for x = -120, 120 do
    for y = -190, 40 do tiles[#tiles + 1] = { name = "refined-concrete", position = { x, y } } end
  end
  surface.set_tiles(tiles)
  local tracks = { control = build_track(surface, -70), economy = build_track(surface, 70) }
  local pairs = {}
  for _, kind in ipairs({ "car", "spider-vehicle", "locomotive" }) do
    local x = kind == "car" and -20 or (kind == "spider-vehicle" and 0 or -70)
    local economy_x = kind == "car" and 20 or (kind == "spider-vehicle" and 45 or 70)
    local control, control_row = make_vehicle(surface, kind, x, kind == "locomotive" and tracks.control or nil)
    local economy, economy_row = make_vehicle(surface, kind, economy_x, kind == "locomotive" and tracks.economy or nil)
    pairs[kind] = { control = control, economy = economy, unavailable = control == nil or economy == nil,
      construction = { control = control_row, economy = economy_row } }
  end
  check(pairs.car.control and pairs.car.economy, "Car positive-control entities must exist")
  check(pairs.car.economy.row.setters.supported, "Car positive-control setters must be retained")
  check(pairs.car.control.row.setter_probe_restored and pairs.car.economy.row.setter_probe_restored, "Car positive-control setter probe must restore before paired work")
  storage.vehicle_economy_probe.surface = surface.index
  storage.vehicle_economy_probe.pairs = pairs
  storage.vehicle_economy_probe.tracks = tracks
  storage.vehicle_economy_probe.car_contribution = car_service.attach_car(pairs.car.economy.entity, factor)
  check(storage.vehicle_economy_probe.car_contribution ~= nil, "Existing Car service positive control must attach")
  pairs.car.economy.row.mapping_applied = storage.vehicle_economy_probe.car_contribution ~= nil
  for _, kind in ipairs({ "spider-vehicle", "locomotive" }) do
    local pair = pairs[kind]
    if not pair.unavailable then
      if pair.economy.row.fuel.coal_inserted then
        pair.economy.row.mapping_applied, pair.economy.row.mapping_apply_reason = apply_setters(pair.economy.entity, pair.economy.row.setters)
      else
        pair.economy.row.mapping_applied = false
        pair.economy.row.mapping_apply_reason = "not-applied-without-compatible-coal-fuel"
      end
    end
  end
  for _, kind in ipairs({ "car", "spider-vehicle", "locomotive" }) do
    local pair = pairs[kind]
    if not pair.unavailable then
      local reason
      if not pair.economy.row.setters.supported then reason = "efficiency-setters-unsupported-or-unreadable" end
      if not reason and not pair.control.row.fuel.coal_inserted then reason = "control-vehicle-fuel-unavailable: " .. (pair.control.row.fuel.reason or "coal-not-inserted") end
      if not reason and not pair.economy.row.fuel.coal_inserted then reason = "economy-vehicle-fuel-unavailable: " .. (pair.economy.row.fuel.reason or "coal-not-inserted") end
      if not reason and kind == "locomotive" and (not pair.control.row.track or pair.control.row.track.built == 0 or not pair.economy.row.track or pair.economy.row.track.built == 0) then reason = "locomotive-rail-workspace-unavailable" end
      if not reason and not pair.economy.row.mapping_applied then reason = "efficiency-setter-application-unavailable: " .. (pair.economy.row.mapping_apply_reason or "unknown") end
      if reason then
        set_work_unattempted(pair, reason)
      else
        pair.control.row.work = start_manual_work(surface, pair.control.entity, { x = pair.control.entity.position.x, y = pair.control.entity.position.y })
        pair.economy.row.work = start_manual_work(surface, pair.economy.entity, { x = pair.economy.entity.position.x, y = pair.economy.entity.position.y })
        pair.control.row.start_energy, pair.control.row.energy_reason = fuel_energy(pair.control.entity)
        pair.economy.row.start_energy, pair.economy.row.energy_reason = fuel_energy(pair.economy.entity)
      end
    end
  end
  capture_motion(storage.vehicle_economy_probe, event.tick)
end

local function finish_probe(state, tick)
  local result = { status = "passed", scope = "package-excluded-VEH-02-native-capability-probe; no-service-or-support-admission", assertions = assertions,
    tick = tick, factor = factor, tracks = state.tracks, vehicles = {} }
  for _, kind in ipairs({ "car", "spider-vehicle", "locomotive" }) do
    local pair = state.pairs[kind]
    if pair.unavailable then
      result.vehicles[kind] = { decision = "not-admitted-by-this-probe", reason = "entity-construction-unavailable", construction = pair.construction }
    else
      local finish_mapping
      if kind == "car" then
        finish_mapping = function()
          local clean = car_service.detach_car(state.car_contribution)
          if clean then return true, nil end
          return false, "existing-car-control-preserved-an-external-conflict"
        end
      else
        finish_mapping = restore_setters
      end
      result.vehicles[kind] = complete_pair(kind, pair.control, pair.economy, finish_mapping)
    end
  end
  local car = result.vehicles.car
  local car_positive = car.work.measurable and car.work.ratio_matches and car.economy.setter_restored
  if not car_positive then
    result.status = "failed-car-positive-control"
    result.failure = "Existing Car positive control did not measure equal-distance, matched-motion 20 percent fuel reduction with restoration"
  end
  result.assertions = assertions
  state.phase = "complete"
  helpers.write_file("vehicle-economy-capabilities.json", helpers.table_to_json(result), false)
  if not car_positive then error(result.failure) end
end

script.on_nth_tick(1, function(event)
  local state = storage.vehicle_economy_probe
  if not state then
    initialize_probe(event)
    return
  end
  if state.phase ~= "running" then return end
  state.elapsed = (state.elapsed or 0) + 1
  if state.elapsed % 50 == 0 then capture_motion(state, state.elapsed) end
  if state.elapsed >= 300 then finish_probe(state, state.elapsed) end
end)

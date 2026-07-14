local source = data.raw.beacon and data.raw.beacon.beacon
if source then
  local beacon = table.deepcopy(source)
  beacon.name = "mir-fixture-zero-watt-beacon"
  beacon.localised_name = {"entity-name.beacon"}
  beacon.minable = nil
  if settings.startup["mir-prototype-positive-power-floor"].value == true then
    beacon.energy_usage = "0W"
  else
    beacon.energy_usage = "1W"
  end
  data:extend({beacon})
end

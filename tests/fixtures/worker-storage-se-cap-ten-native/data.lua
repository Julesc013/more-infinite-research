-- Fixture-owned electricity and an unrelated eligible tail.  Neither alters
-- the published SE lab, MIR technology, science unit, cost, time, or effect.
local interface = table.deepcopy(data.raw["electric-energy-interface"]["electric-energy-interface"])
interface.name = "mir-fixture-worker-storage-se-cap-ten-power"
interface.localised_name = {"entity-name.electric-energy-interface"}
interface.energy_source = {
  type = "electric",
  usage_priority = "primary-output",
  buffer_capacity = "50MJ",
  input_flow_limit = "0W",
  output_flow_limit = "25MW"
}
interface.energy_production = "25MW"
interface.energy_usage = "0W"
interface.minable = {mining_time = 0.1, result = "electric-energy-interface"}

data:extend({
  interface,
  {
    type = "technology",
    name = "mir-fixture-worker-storage-se-cap-ten-tail",
    icon = "__base__/graphics/technology/automation.png",
    icon_size = 256,
    prerequisites = {"automation-science-pack"},
    unit = {count = 1, time = 1, ingredients = {{"automation-science-pack", 1}}},
    effects = {}
  }
})

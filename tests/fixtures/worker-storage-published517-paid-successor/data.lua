-- Fixture-owned electricity for the ordinary lab research.
local interface = table.deepcopy(data.raw["electric-energy-interface"]["electric-energy-interface"])
interface.name = "mir-fixture-published517-earned-source-power"
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

data:extend({interface})

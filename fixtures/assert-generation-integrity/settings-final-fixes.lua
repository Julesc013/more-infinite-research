local expected_double_defaults = {
  ["ips-effect-per-level-research_furnace"] = {20, 40},
  ["ips-effect-per-level-research_belts"] = 10,
  ["ips-effect-per-level-research_carbon"] = 10,
  ["ips-effect-per-level-research_lithium"] = 10,
  ["ips-effect-per-level-research_robot_battery"] = 10,
  ["ips-effect-per-level-research_spoilage_preservation"] = {1, 2},
  ["ips-effect-per-level-research_agricultural_growth_speed"] = {1, 2},
  ["mir-effect-per-level-braking-force"] = 15,
  ["mir-effect-per-level-laser-shooting-speed"] = 50,
  ["mir-effect-per-level-research-speed"] = 60,
  ["mir-effect-per-level-weapon-shooting-speed"] = 40
}

local expected_int_defaults = {
  ["ips-effect-per-level-research_character_reach"] = 10,
  ["ips-effect-per-level-research_inventory_capacity"] = 1,
  ["mir-effect-per-level-inserter-capacity-bonus"] = 4,
  ["mir-effect-per-level-worker-robots-storage"] = 1
}

local function assert_defaults(prototype_type, expected)
  local prototypes = data.raw[prototype_type] or {}
  for name, accepted in pairs(expected) do
    local prototype = prototypes[name]
    if not prototype then
      error("MIR fixture missing effect-per-level setting prototype " .. name)
    end
    local values = type(accepted) == "table" and accepted or {accepted}
    local matches = false
    for _, value in ipairs(values) do
      if prototype.default_value == value then matches = true end
    end
    if not matches then
      error("MIR fixture expected " .. name .. " primary-tier default "
        .. table.concat(values, " or ") .. ", got " .. tostring(prototype.default_value))
    end
  end
end

assert_defaults("double-setting", expected_double_defaults)
assert_defaults("int-setting", expected_int_defaults)

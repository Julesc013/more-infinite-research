local owner = data.raw.technology and data.raw.technology["processing-unit-productivity"]
if not owner then error("MIR fixed-count fixture requires processing-unit-productivity") end
owner.unit.count = 1000
owner.unit.count_formula = nil

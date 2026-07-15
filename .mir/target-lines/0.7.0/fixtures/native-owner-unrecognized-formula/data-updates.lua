local owner = data.raw.technology and data.raw.technology["processing-unit-productivity"]
if not owner then error("MIR unrecognized-formula fixture requires processing-unit-productivity") end
owner.unit.count = nil
owner.unit.count_formula = "1000 + 100 * L"

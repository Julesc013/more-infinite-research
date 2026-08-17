local owner = data.raw.technology["processing-unit-productivity"]
if not owner then error("late native-owner maximum-level fixture is missing its owner") end
owner.max_level = 9

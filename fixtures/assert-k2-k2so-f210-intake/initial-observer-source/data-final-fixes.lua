local function sorted_copy(values)
  local out = {}
  for _, value in ipairs(values or {}) do out[#out + 1] = value end
  table.sort(out)
  return out
end

local reference = assert(data.raw.technology["kr-singularity-lab"], "missing native reference technology kr-singularity-lab")
local science = {}
for _, ingredient in ipairs(reference.unit.ingredients or {}) do science[#science + 1] = ingredient[1] or ingredient.name end
table.sort(science)
local labs = {}
for name, lab in pairs(data.raw.lab) do
  local inputs = sorted_copy(lab.inputs)
  local accepts = true
  local allowed = {}
  for _, input in ipairs(inputs) do allowed[input] = true end
  for _, pack in ipairs(science) do if not allowed[pack] then accepts = false end end
  if accepts then labs[#labs + 1] = { id = name, inputs = inputs } end
end
table.sort(labs, function(a, b) return a.id < b.id end)
assert(#labs > 0, "no reachable compatible lab prototype for native reference technology")
log("[MIR4_A03_K2_INTAKE] " .. helpers.table_to_json({schema=1,kind="MIR4A03K2IntakeObservationV1",post_finalizer_observation=true,native_reference_technology={id=reference.name,prerequisites=sorted_copy(reference.prerequisites),science=science},compatible_labs=labs,mutation_authorized=false,package_visible=false}))

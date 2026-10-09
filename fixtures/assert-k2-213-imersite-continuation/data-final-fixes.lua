local function fail(message)
  error("MIR K2 2.1.3 Imersite continuation validation failed: " .. message)
end

local active = {}
for name, version in pairs(mods) do
  if name ~= "core" then active[#active + 1] = name .. "@" .. version end
end
table.sort(active)
log("[MIR_ACTIVE_MODS] " .. table.concat(active, "|"))

local expected = {
  Krastorio2 = "2.1.3",
  ["Krastorio2-spaced-out"] = "2.0.13"
}
if mods["more-infinite-research"] ~= "4.2.21001"
    and mods["more-infinite-research"] ~= "4.2.21002" then fail("unexpected exact MIR candidate") end
if mods.base ~= "2.1.20" and mods.base ~= "2.1.21" then fail("unexpected exact engine") end
for name, version in pairs(expected) do
  if mods[name] ~= version then fail("unexpected exact profile " .. name) end
end

local legacy_name = "recipe-prod-research_material_imersite-1"
local continuation_name = "recipe-prod-research_material_imersite-4"
local native_name = "kr-imersite-productivity"
local legacy = assert(data.raw.technology[legacy_name], "missing MIR Imersite legacy technology")
local continuation = assert(data.raw.technology[continuation_name], "missing MIR Imersite continuation technology")
local native = assert(data.raw.technology[native_name], "missing native Imersite owner")

local function matching_effects(technology, recipe)
  local effects = {}
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe then
      effects[#effects + 1] = effect.change
    end
  end
  return effects
end

local legacy_effects = matching_effects(legacy, "kr-imersite-powder")
local continuation_effects = matching_effects(continuation, "kr-imersite-powder")
local native_crystal_effects = matching_effects(native, "kr-imersite-crystal")
if legacy.max_level ~= 3 then fail("legacy Imersite stage is not finite at level three") end
if continuation.max_level ~= "infinite" then fail("continuation is not lossless on current Factorio") end
if #legacy_effects ~= 1 or legacy_effects[1] ~= 0.02 then fail("legacy powder effect differs") end
if #continuation_effects ~= 1 or continuation_effects[1] ~= 0.02 then
  fail("continuation powder effect differs")
end
if #native_crystal_effects ~= 1 or native_crystal_effects[1] ~= 0.1 then
  fail("native crystal owner differs")
end
if #matching_effects(continuation, "kr-imersite-crystal") ~= 0 then
  fail("continuation widened into the native crystal domain")
end

log("[MIR42_K2_213_IMERSITE_CONTINUATION_DATA] legacy=" .. legacy_name
  .. ";continuation=" .. continuation_name .. ";powder_effect=0.02;native_crystal=" .. native_name)

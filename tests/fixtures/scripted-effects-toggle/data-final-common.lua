local M = {}

local FIXTURE = "mir-fixture-mir5-scripted-effects-toggle"
local AGRICULTURE = "recipe-prod-research_agricultural_growth_speed-1"
local SPOILAGE = "recipe-prod-research_spoilage_preservation-1"
local SPOIL_TICKS = 600

local expected = {
  [AGRICULTURE] = {
    formula = "40000*1.5^(L-1)", time = 90,
    science = {
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
      "cryogenic-science-pack"
    }
  },
  [SPOILAGE] = {
    formula = "50000*1.5^(L-1)", time = 120,
    science = {
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "production-science-pack", "space-science-pack", "agricultural-science-pack",
      "cryogenic-science-pack"
    }
  }
}

local function names(values, wanted, label)
  assert(type(values) == "table" and #values == #wanted, label .. " count changed")
  for index, name in ipairs(wanted) do
    local value = values[index]
    local actual = type(value) == "table" and (value.name or value[1]) or value
    assert(actual == name, label .. " changed at " .. tostring(index))
    if type(value) == "table" then assert((value.amount or value[2]) == 1, label .. " amount changed") end
  end
end

local function exact_mods(version)
  local wanted = {
    base = "2.0.77", ["elevated-rails"] = "2.0.77", quality = "2.0.77", ["space-age"] = "2.0.77",
    ["more-infinite-research"] = "5.0.20000",
    ["mir-fixture-mir5-active-mods-observer"] = "0.1.0", [FIXTURE] = version
  }
  for name, actual in pairs(mods) do assert(wanted[name] == actual, "unexpected toggle fixture closure member " .. tostring(name)) end
  for name, wanted_version in pairs(wanted) do assert(mods[name] == wanted_version, "missing toggle fixture closure member " .. name) end
end

local function check_setting(name, enabled)
  local runtime = assert(settings.startup and settings.startup[name], "toggle runtime setting is absent: " .. name)
  assert(runtime.value == enabled, "toggle runtime setting differs: " .. name)
end

local function check_row(name, enabled)
  local row = assert(data.raw.technology and data.raw.technology[name], "captured scripted row is absent: " .. name)
  local facts = expected[name]
  assert(row.type == "technology" and row.name == name and row.level == 1 and row.max_level == "infinite" and row.upgrade == true,
    "captured scripted identity differs: " .. name)
  assert((row.enabled ~= false) == enabled, "captured scripted enabled state differs: " .. name)
  assert(type(row.unit) == "table" and row.unit.count == nil and row.unit.count_formula == facts.formula and row.unit.time == facts.time,
    "captured scripted unit differs: " .. name)
  names(row.prerequisites, facts.science, "captured scripted prerequisites " .. name)
  names(row.unit.ingredients, facts.science, "captured scripted science " .. name)
  assert(type(row.effects) == "table" and #row.effects == 1 and row.effects[1].type == "nothing"
    and type(row.effects[1].effect_description) == "table" and row.effects[1].effect_description[2] == "1",
    "captured scripted effect differs: " .. name)
  row.unit.count_formula, row.unit.count, row.unit.time = nil, 1, 1
end

function M.accelerate(spec)
  assert(type(spec) == "table" and type(spec.version) == "string" and type(spec.enabled) == "boolean", "invalid toggle fixture stage")
  exact_mods(spec.version)
  check_setting("ips-enable-research_agricultural_growth_speed", spec.enabled)
  check_setting("ips-enable-research_spoilage_preservation", spec.enabled)
  check_row(AGRICULTURE, spec.enabled)
  check_row(SPOILAGE, spec.enabled)
  local yumako = assert(data.raw.capsule and data.raw.capsule.yumako, "native yumako is absent")
  assert(yumako.spoil_ticks == 216000 and yumako.spoil_result == "spoilage", "native yumako spoilage differs")
  yumako.spoil_ticks = SPOIL_TICKS
end

return M

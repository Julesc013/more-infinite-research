-- Small settings-stage catalogue; no prototype-world or Generator imports.
local M = {}
local key = "research_gears"
local fields = {
  {key = "enabled", name = "ips-enable-", type = "bool-setting", default_value = true},
  {key = "base_cost", name = "ips-cost-base-", type = "int-setting", default_value = 8000, minimum_value = 1, maximum_value = 2147483647},
  {key = "linear_increment", name = "ips-cost-linear-increment-", type = "int-setting", default_value = 0, minimum_value = 0, maximum_value = 2147483647},
  {key = "growth_factor", name = "ips-cost-growth-", type = "double-setting", default_value = 2, minimum_value = 1},
  {key = "max_level", name = "ips-max-level-", type = "int-setting", default_value = 0, minimum_value = 0, maximum_value = 2147483647},
  {key = "research_time", name = "ips-research-time-", type = "int-setting", default_value = 60, minimum_value = 0, maximum_value = 2147483647},
  {key = "effect_percent", name = "ips-effect-per-level-", type = "double-setting", default_value = 10, minimum_value = 0.01, maximum_value = 1000000}
}

local function valid(spec, value)
  if spec.type == "bool-setting" then return type(value) == "boolean" end
  return type(value) == "number" and value == value and value < math.huge
    and value >= spec.minimum_value and (not spec.maximum_value or value <= spec.maximum_value)
    and (spec.type ~= "int-setting" or value == math.floor(value))
end

function M.prototypes()
  local out = {{
    type = "string-setting", name = "mir-settings-profile-import", setting_type = "startup",
    default_value = "", allow_blank = true, order = "a-7-010",
    localised_name = {"mod-setting-name.mir-settings-profile-import"},
    localised_description = {"mod-setting-description.mir-settings-profile-import"}
  }}
  for index, spec in ipairs(fields) do
    out[#out + 1] = {
      type = spec.type, name = spec.name .. key, setting_type = "startup",
      default_value = spec.default_value, minimum_value = spec.minimum_value,
      maximum_value = spec.maximum_value,
      order = "b-100-iron-gear-wheel-productivity-stream-research_gears-" .. (index - 1),
      localised_name = {"mod-setting-name." .. spec.name .. "stream", {"technology-name.more-infinite-research.research_gears"}},
      localised_description = {"mod-setting-description." .. spec.name .. "stream", {"technology-name.more-infinite-research.research_gears"}}
    }
  end
  return out
end

local function profile(startup, codec, report)
  local setting = startup["mir-settings-profile-import"]
  local text = setting and setting.value
  if not text or text == "" then return nil end
  local function decode()
    if not (codec and codec.json_to_table and codec.decode_string and codec.encode_string) then return nil end
    local json = text
    if text:sub(1, 8) == "MIRSET1:" then
      json = codec.decode_string(text:sub(9))
    elseif not text:match("^%s*{") then
      return nil
    end
    if not json then return nil end
    local decoded = codec.json_to_table(json)
    if type(decoded) ~= "table" or decoded.schema ~= 1
      or (decoded.kind ~= nil and decoded.kind ~= "mir-settings-profile")
      or type(decoded.settings) ~= "table" then return nil end
    return decoded.settings
  end
  local ok, decoded = pcall(decode)
  if ok and decoded then return decoded end
  if report then report("[more-infinite-research] Ignoring invalid MIR settings profile import") end
  return nil
end

function M.resolve(startup, codec, report)
  local imported = profile(startup, codec, report)
  local values = {}
  for _, spec in ipairs(fields) do
    local name = spec.name .. key
    local setting = startup[name]
    local value = setting and setting.value
    if value == nil then value = spec.default_value end
    if imported and setting and imported[name] ~= nil and valid(spec, imported[name]) then value = imported[name] end
    assert(valid(spec, value), "MIR invalid effective setting: " .. name)
    values[spec.key] = value
  end
  if values.research_time == 0 then values.research_time = 60 end
  return values
end

return M

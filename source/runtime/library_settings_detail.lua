-- Stateless renderer for the selected Settings detail pane.
--
-- The Library owns the selected group, native GUI lifetime and every player
-- view/cache decision. This helper receives the existing owned pane plus the
-- immutable catalogue row and creates only its detail children.
local M = {}

local function style_pixels(value)
  return math.max(1, math.floor(value))
end

-- A valid UTF-8 input must remain valid when the compact display preview is
-- bounded by bytes.
local function utf8_prefix(value, limit)
  local last = math.min(#value, limit)
  local lead = last
  while lead > 0 do
    local byte = string.byte(value, lead)
    if byte < 128 or byte > 191 then break end
    lead = lead - 1
  end
  if lead == 0 then return "" end
  local first = string.byte(value, lead)
  local size = first < 128 and 1 or first < 224 and 2 or first < 240 and 3 or 4
  if lead + size - 1 > last then last = lead - 1 end
  return string.sub(value, 1, last)
end

local function setting_display(name, value)
  if type(value) == "boolean" then return {"mir-browser.setting-" .. (value and "on" or "off")} end
  if type(value) == "number" and value == 0 and type(name) == "string"
      and name:find("%-max%-level%-", 1) then
    return {"mir-browser.setting-unlimited"}
  end
  if type(value) == "number" and value == value and math.abs(value) ~= math.huge then
    local compact = string.format("%.6g", value)
    return tonumber(compact) == value and compact or "≈ " .. compact
  end
  local shown = tostring(value)
  if #shown > 120 then return utf8_prefix(shown, 117) .. "..." end
  return shown
end

local function section(options, parent, name, caption, width)
  local prefix, add = options.prefix, options.add
  local divider = add(parent, {type = "line", name = prefix .. name .. "_divider", direction = "horizontal"})
  divider.style.width = math.max(1, width - 16)
  divider.style.top_margin, divider.style.bottom_margin = options.section_gap, options.control_gap
  local heading = add(parent, {type = "label", name = prefix .. name, caption = {caption}})
  heading.style.font, heading.style.bottom_margin = "default-bold", 4
end

function M.render(options)
  local parent, selected = options.parent, options.selected
  local prefix, add, valid = options.prefix, options.add, options.valid
  local detail_width = options.detail_width

  local function setting_label(spec, label_parent, width)
    local label = add(label_parent or parent, spec)
    if valid(label) and label.style then
      label.style.single_line = false
      label.style.maximal_width = math.max(1, width or detail_width - 16)
    end
    return label
  end

  if selected == nil then
    setting_label({type = "label", name = prefix .. "settings_empty", caption = {"mir-browser.settings-empty"}})
    return
  end

  local title = setting_label({type = "label", name = prefix .. "settings_title", caption = selected.title})
  title.style.font = "default-large-bold"
  setting_label({type = "label", name = prefix .. "settings_scope", caption = {"mir-browser.scope-startup"}})
  if selected.externally_supplied then
    setting_label({type = "label", name = prefix .. "settings_external", caption = {"mir-browser.settings-external-owner"}})
  end
  section(options, parent, "settings_effective", "mir-browser.effective-values", detail_width)
  local fields = add(parent, {type = "table", name = prefix .. "settings_fields", column_count = 2})
  fields.style.width = math.max(1, detail_width - 16)
  fields.style.horizontal_spacing, fields.style.vertical_spacing = 12, 10
  local field_width = math.max(1, style_pixels((detail_width - 40) * .55))
  local value_width = math.max(1, detail_width - 40 - field_width)
  local source = "default"
  for index, field in ipairs(selected.fields) do
    local name = prefix .. "setting_" .. index
    local label = setting_label({type = "label", name = name .. "_name", caption = field.caption,
      tooltip = field.description}, fields, field_width)
    label.style.font = "default-semibold"
    local display = setting_display(field.name, field.effective)
    if field.default ~= nil and field.effective ~= field.default then
      display = {"mir-browser.setting-with-default", display, setting_display(field.name, field.default)}
    end
    setting_label({type = "label", name = name .. "_value", caption = display,
      tooltip = {"mir-browser.setting-provenance", setting_display(field.name, field.direct),
        setting_display(field.name, field.default), {"mir-browser.source-" .. field.source}}}, fields, value_width)
    if field.source == "mirset1" then
      source = "mirset1"
      setting_label({type = "label", name = name .. "_profile_marker", caption = {"mir-browser.profile-override"}}, fields, field_width)
      setting_label({type = "label", name = name .. "_source", caption = {"mir-browser.source-mirset1"}}, fields, value_width)
    elseif source ~= "mirset1" and field.source == "direct" then
      source = "direct"
    end
  end
  section(options, parent, "settings_source", "mir-browser.configuration-source", detail_width)
  setting_label({type = "label", name = prefix .. "settings_source_summary", caption = {"mir-browser.source-" .. source}})
end

return M

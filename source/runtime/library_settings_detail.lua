-- Stateless renderer for the selected Settings detail pane.
--
-- The Library owns the selected group, native GUI lifetime and every player
-- view/cache decision. This helper receives the existing owned pane plus the
-- immutable catalogue row and creates only its detail children.
local M = {}

function M.render(options)
  local parent, selected = options.parent, options.selected
  local prefix, add, valid = options.prefix, options.add, options.valid
  local display, section, pixels = options.display, options.section, options.pixels
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
  section(parent, "settings_effective", "mir-browser.effective-values", detail_width)
  local fields = add(parent, {type = "table", name = prefix .. "settings_fields", column_count = 2})
  fields.style.width = math.max(1, detail_width - 16)
  fields.style.horizontal_spacing, fields.style.vertical_spacing = 12, 10
  local field_width = math.max(1, pixels((detail_width - 40) * .55))
  local value_width = math.max(1, detail_width - 40 - field_width)
  local source = "default"
  for index, field in ipairs(selected.fields) do
    local name = prefix .. "setting_" .. index
    local label = setting_label({type = "label", name = name .. "_name", caption = field.caption,
      tooltip = field.description}, fields, field_width)
    label.style.font = "default-semibold"
    local value = display(field.name, field.effective)
    if field.default ~= nil and field.effective ~= field.default then
      value = {"mir-browser.setting-with-default", value, display(field.name, field.default)}
    end
    setting_label({type = "label", name = name .. "_value", caption = value,
      tooltip = {"mir-browser.setting-provenance", display(field.name, field.direct),
        display(field.name, field.default), {"mir-browser.source-" .. field.source}}}, fields, value_width)
    if field.source == "mirset1" then
      source = "mirset1"
      setting_label({type = "label", name = name .. "_profile_marker", caption = {"mir-browser.profile-override"}}, fields, field_width)
      setting_label({type = "label", name = name .. "_source", caption = {"mir-browser.source-mirset1"}}, fields, value_width)
    elseif source ~= "mirset1" and field.source == "direct" then
      source = "direct"
    end
  end
  section(parent, "settings_source", "mir-browser.configuration-source", detail_width)
  setting_label({type = "label", name = prefix .. "settings_source_summary", caption = {"mir-browser.source-" .. source}})
end

return M

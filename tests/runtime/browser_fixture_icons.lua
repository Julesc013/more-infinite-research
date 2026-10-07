-- Post-MIR checks for the selected base-only graphical acceptance case.
-- Native loading/rendering still belongs to the caller, not this assertion.
return function(expected)
  local name = "mir-use-installed-space-age-icons"
  assert(not mods["space-age"] and not mods["elevated-rails"], "Icon fixture requires inactive DLC providers")
  local codec = require("__more-infinite-research__.prototypes.mir.settings.profile_codec")
  local effective = require("__more-infinite-research__.prototypes.mir.settings.effective")
  local raw = settings.startup[name].value
  local imported_text = settings.startup[codec.import_setting_name].value
  local imported, decoded
  if imported_text ~= "" then
    assert(imported_text:sub(1, #codec.prefix) == codec.prefix, "Fixture must exercise MIRSET1 decoding")
    decoded = assert(codec.decode(imported_text))
    imported = decoded.settings[name]
  end
  assert(raw == expected.raw and imported == expected.imported, "Native icon settings differ from selected case")
  local expected_effective = expected.imported
  if expected_effective == nil then expected_effective = expected.raw end
  assert(effective.get(name) == expected_effective, "Native imported setting precedence differs")

  local shortcut = assert(data.raw.shortcut["mir-research-browser"], "Library shortcut is absent")
  assert(shortcut.icon == "__base__/graphics/icons/lab.png" and shortcut.small_icon == shortcut.icon
    and shortcut.icon_size == 64 and shortcut.small_icon_size == 64, "Both shortcut sizes must use base fallback")
  local strings = 0
  local function inspect(value)
    if type(value) == "table" then
      for _, child in pairs(value) do inspect(child) end
    elseif type(value) == "string" then
      strings = strings + 1
      for _, provider in ipairs({"space-age", "elevated-rails"}) do
        assert(not value:find("__" .. provider .. "__/", 1, true), "Inactive DLC resource in final technology/shortcut: " .. value)
      end
    end
  end
  local technologies = 0
  for _, technology in pairs(data.raw.technology or {}) do
    technologies = technologies + 1
    inspect(technology)
  end
  for _, value in pairs(data.raw.shortcut or {}) do inspect(value) end
  assert(technologies > 0 and strings > 0, "Final artwork scan is empty")
  log("[mir-browser-icons] PASS " .. helpers.table_to_json{
    case = expected.case, raw = raw, imported = imported, effective = expected_effective,
    technologies = technologies, strings = strings, inactive_provider_references = 0,
    shortcut_icon = shortcut.icon, shortcut_small_icon = shortcut.small_icon,
    boundary = "DLC inactive; physical installation absence not established"
  })
end

local fixture = "mir-fixture-mir5-migration-origin-f200-100-source"
if mods.base ~= "2.0.77" or mods["more-infinite-research"] ~= "1.0.0"
    or mods[fixture] ~= "0.1.0" then
  error("[mir5-migration-origin-f200-100-source] source settings closure differs")
end

-- F200 has no Space Age recipes, so this existing source setting cannot alter
-- the F200 source roster. Keeping its effective value nondefault makes the
-- saved setting state an explicit later-successor input rather than assuming
-- every historical source save used defaults.
local setting = assert(data.raw["bool-setting"] and data.raw["bool-setting"]["ips-enable-research_breeding"],
  "[mir5-migration-origin-f200-100-source] source breeding setting is absent")
assert(setting.setting_type == "startup" and setting.default_value == true,
  "[mir5-migration-origin-f200-100-source] source breeding setting differs")
setting.default_value = false

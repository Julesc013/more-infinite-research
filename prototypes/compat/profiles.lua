local P = {}

local function apply_profile(config, profile)
  if profile.streams then
    for key, patch in pairs(profile.streams) do
      config.streams[key] = config.streams[key] or {}
      for field, value in pairs(patch) do
        config.streams[key][field] = value
      end
    end
  end
end

local PROFILES = {
  -- This table is intentionally small for now. It gives future compatibility
  -- work a stable place for mod-specific stream patches without bloating the
  -- base stream definitions.
}

function P.apply(config)
  for mod_name, profile in pairs(PROFILES) do
    if mods and mods[mod_name] then
      apply_profile(config, profile)
    end
  end
end

return P

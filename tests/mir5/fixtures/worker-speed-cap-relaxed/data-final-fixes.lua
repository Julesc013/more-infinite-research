local setting = data.raw["int-setting"] and data.raw["int-setting"]["mir-max-level-worker-robots-speed"]
if not setting or setting.default_value ~= 0 then
  error("[mir5-worker-speed-cap-relaxed] unlimited startup sentinel differs")
end

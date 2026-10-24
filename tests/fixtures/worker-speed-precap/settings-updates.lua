local setting = data.raw["int-setting"]["mir-max-level-worker-robots-speed"]
-- This predecessor must have no finite-cap handler while native level setters
-- establish its baseline. The successor qualifies the actual config change.
setting.minimum_value, setting.maximum_value, setting.default_value = -1, 0, 0

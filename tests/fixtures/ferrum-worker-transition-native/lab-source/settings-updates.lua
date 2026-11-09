local caps, switches = data.raw["int-setting"], data.raw["bool-setting"]
if caps and caps["mir-max-level-worker-robots-storage"] then caps["mir-max-level-worker-robots-storage"].default_value=8 end
if switches and switches["mir-enable-worker-robots-storage"] then switches["mir-enable-worker-robots-storage"].default_value=true end

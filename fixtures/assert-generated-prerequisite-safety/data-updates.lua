local anchor = data.raw.technology and data.raw.technology["worker-robots-storage-3"]
if not anchor then
  error("MIR generated prerequisite safety fixture requires worker-robots-storage-3.")
end

anchor.enabled = false

local technology = data.raw.technology["recipe-prod-research_copper-1"]
if not technology then error("MIR generated maximum-level fixture is missing copper productivity") end
if technology.max_level ~= "infinite" then
  error("MIR generated maximum-level fixture requires a lossless infinite prototype")
end

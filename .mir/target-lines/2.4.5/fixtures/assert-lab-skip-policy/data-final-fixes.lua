local tech = data.raw.technology and data.raw.technology["recipe-prod-research_science_pack_productivity-1"]

if tech then
  error("MIR validation failed: lab incompatibility policy skip did not skip science-pack productivity.")
end

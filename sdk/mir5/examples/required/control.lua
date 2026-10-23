-- The hard dependency makes MIR active. Query only once game state exists;
-- this runtime consumer never imports a MIR module.
script.on_init(function()
  local interface = remote.interfaces["more-infinite-research.api.v1"]
  assert(interface and interface.get_research, "Missing candidate MIR query API")
  local version = remote.call("more-infinite-research.api.v1", "get_version")
  assert(version and version.major == 1, "Unsupported MIR API major")
  local capabilities = remote.call("more-infinite-research.api.v1", "get_capabilities")
  assert(capabilities and capabilities.research_query == true, "MIR research query is unavailable")
  local value, code = remote.call("more-infinite-research.api.v1", "get_research",
    game.forces.player.index, "mir-api-example-required-gears-1")
  assert(value and value.name == "mir-api-example-required-gears-1", tostring(code))
end)

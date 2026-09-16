local raw_catalog = require("prototypes.mir.domain.streams.raw_catalog")

return raw_catalog.merge_unique({
  { name = "productivity", streams = require("prototypes.streams.productivity") },
  { name = "direct-effects", streams = require("prototypes.streams.direct-effects") }
})

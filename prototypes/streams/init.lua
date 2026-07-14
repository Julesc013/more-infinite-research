local streams = {}

local function merge(source)
  for key, spec in pairs(source) do
    streams[key] = spec
  end
end

merge(require("prototypes.streams.productivity"))
merge(require("prototypes.streams.direct-effects"))

return streams

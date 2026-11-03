local startup_trace = require("startup_diagnostics").start("settings")
data:extend(require("research.settings").prototypes())
startup_trace.phase("stage", "end")

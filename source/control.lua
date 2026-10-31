-- Parse-time composition only. remote.add_interface registration and every
-- named event binding live in runtime.bootstrap; no handler imports modules
-- after control parsing.
local bootstrap = require("runtime.bootstrap")

bootstrap.register()

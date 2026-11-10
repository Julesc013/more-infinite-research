-- Target archive ONLY: read native state before any configuration reconciliation.
local probe = require("__mir-fixture-worker-default-snapshot__/snapshot")
probe.observe("lua-migration-entry")

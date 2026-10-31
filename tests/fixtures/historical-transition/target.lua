-- The runner stamps the immutable target and either published or MIR5 stage
-- into target-literal.lua.  This shared file has no platform inference.
return require("target-literal")

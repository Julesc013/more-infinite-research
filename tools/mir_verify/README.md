# MIR verification tool

This directory is the stable tool entrypoint requested by the verification architecture. `Invoke-MIRVerify.ps1` is intentionally a thin forwarding shim: the authoritative planner, fingerprinting, evidence ledger, worker, and aggregate-gate implementation remains `scripts/Invoke-MIRAssurance.ps1`, so MIR has one verifier rather than two competing implementations.

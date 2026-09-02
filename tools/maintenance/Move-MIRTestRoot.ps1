# MIR4-HISTORICAL-MIGRATION-STATUS
[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")),
  [switch]$Apply
)

$ErrorActionPreference = "Stop"

if ($Apply) {
  throw "[mir-test-root-migration-retired] The executable-test cutover is complete; current tests belong under tests/."
}

[ordered]@{
  schema = 2
  migration = "mir-test-root-v1"
  mode = "historical-complete"
  tests = 65
  canonical_root = "tests"
  compatibility_root = "validation/tests"
  changed = 0
} | ConvertTo-Json

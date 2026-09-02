# MIR4-CANONICAL-EXECUTABLE-TEST
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$command = Join-Path $repo 'tools\mir\cli\Invoke-MIR4ExperimentalApi.ps1'

foreach ($operation in @('sdk-check', 'api-check', 'api-conformance')) {
  & $command -Command $operation -RepoRoot $repo
}

$lua = Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk\experimental\mir4\lua\mir4_api_v0.lua')
$requiredLuaChecks = @(
  "type(v.target) ~= 'table'",
  "type(v.versions) ~= 'table'",
  "type(v.payload) ~= 'table'",
  "string.match(v.target.id, '^f%d%d%d$')",
  "string.match(v.target.factorio_line, '^%d+%.%d+$')",
  '#v.capabilities > 128',
  'seen[capability]',
  'valid_capability(capability)',
  'valid_namespace(namespace)',
  'extension_count > 32',
  "v.canonicalization ~= 'mir-canonical-json-v0'",
  "string.match(v.digest, '^sha256:[0-9a-f]+$')",
  '#v.digest ~= 71'
)
foreach ($needle in $requiredLuaChecks) {
  if (-not $lua.Contains($needle)) {
    throw "[mir4-api-lua-validator] Generated Lua validator is missing check: $needle"
  }
}

$experimentalPaths = @(
  'sdk/experimental/mir4',
  'spec/api/mir4-v0',
  'spec/schemas/experimental',
  'fixtures/mir4-api-v0',
  'docs/reference/generated/mir4-experimental-api-v0.md',
  'tools/mir/application/extensions/ExperimentalApiSdk.ps1',
  'tools/mir/cli/Invoke-MIR4ExperimentalApi.ps1',
  'tools/lib/mir4/ExperimentalApiSdk.ps1',
  'tools/commands/mir4/Invoke-MIR4ExperimentalApi.ps1',
  'tests/mir4/Test-MIR4ExperimentalApiSdk.ps1'
)
. (Join-Path $repo 'tools\lib\validation\PackageIdentity.ps1')
$shipped = @(Get-MIRPackageSourceFiles -RepoRoot $repo)
foreach ($path in $experimentalPaths) {
  $matches = @($shipped | Where-Object { $_ -eq $path -or $_.StartsWith($path.TrimEnd('/') + '/') })
  if ($matches.Count -gt 0) {
    throw "[mir4-api-package-visible] Experimental artifact entered package: $path"
  }
}
Write-Host 'MIR4 experimental API/SDK validation passed.'

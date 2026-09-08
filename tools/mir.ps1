param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = 'Stop'

# Sole supported public entry point. Parsing, command lookup, application
# invocation, and rendering live in the package-excluded CLI layer.
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$router = Join-Path $repo 'tools/mir/cli/Invoke-MIRCommandRouter.ps1'
& $router @Args
if ($Args.Count -ge 2 -and $Args[0] -ceq 'release' -and $Args[1] -ceq 'doctor' -and $LASTEXITCODE -eq 2) { exit 2 }

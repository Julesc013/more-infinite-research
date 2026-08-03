param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
& (Join-Path $repo "scripts/mir.ps1") @Args
exit $LASTEXITCODE
